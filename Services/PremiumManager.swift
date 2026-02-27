//
//  PremiumManager.swift
//  GokigenNote
//
//  課金状態と使用回数制限を一箇所で管理。
//  共通枠（rewriteQuota）で言い換え・共感を合算。
//

import Foundation
import StoreKit
import Combine
import SwiftUI
import OSLog
import FirebaseFunctions

enum SubscriptionType: Equatable {
    case monthly
    case yearly
}

enum Plan: Equatable {
    case free
    case lifetime
    case subscription(SubscriptionType)
}

extension Plan {
    /// ローカルキャッシュ用（オフライン耐性）
    static func from(cacheValue: String) -> Plan? {
        switch cacheValue {
        case "free": return .free
        case "lifetime": return .lifetime
        case "monthly": return .subscription(.monthly)
        case "yearly": return .subscription(.yearly)
        default: return nil
        }
    }

    /// サーバー（syncEntitlements）の plan 文字列から変換。サーバーを正とするときに使用。
    static func from(serverValue: String) -> Plan? {
        switch serverValue {
        case "free": return .free
        case "lifetime": return .lifetime
        case "subscription_monthly": return .subscription(.monthly)
        case "subscription_yearly": return .subscription(.yearly)
        default: return nil
        }
    }

    var cacheValue: String {
        switch self {
        case .free: return "free"
        case .lifetime: return "lifetime"
        case .subscription(.monthly): return "monthly"
        case .subscription(.yearly): return "yearly"
        }
    }

    var displayName: String {
        switch self {
        case .free: return "無料"
        case .lifetime: return "買い切り"
        case .subscription(.monthly): return "プレミアム（月額）"
        case .subscription(.yearly): return "プレミアム（年額）"
        }
    }

    var isPremium: Bool {
        switch self {
        case .free: return false
        case .lifetime, .subscription: return true
        }
    }

    /// 回数制限。nil = 無制限
    var rewriteLimit: Int? {
        switch self {
        case .free: return 10
        case .lifetime: return 200
        case .subscription: return nil
        }
    }

    var description: String {
        switch self {
        case .free: return "1日10回まで利用可能"
        case .lifetime: return "月200回まで利用可能"
        case .subscription: return "無制限で利用可能"
        }
    }
}

enum ProductID {
    static let premiumMonthly = "gokigen.premium.monthly"
    static let premiumYearly = "gokigen.premium.yearly"
    static let lifetime = "gokigen.lifetime"

    /// 取得トライ用（ASC未作成のIDだけ落ちる。空になるのは別要因も疑う）
    static let all: Set<String> = [
        premiumMonthly,
        premiumYearly,
        lifetime,
    ]

    static func subscriptionType(for productID: String) -> SubscriptionType? {
        switch productID {
        case premiumMonthly: return .monthly
        case premiumYearly: return .yearly
        default: return nil
        }
    }

    /// Paywall表示用ラベル（ID直書き排除）
    static func displayName(for id: String) -> String {
        switch id {
        case premiumMonthly: return "プレミアム（月額）"
        case premiumYearly: return "プレミアム（年額）"
        case lifetime: return "買い切り（Lifetime）"
        default: return "不明な商品"
        }
    }

    /// Paywall表示順（型に寄せる＝追加時の更新漏れ防止）
    static func sortKey(for id: String) -> Int {
        switch id {
        case premiumMonthly: return 10
        case premiumYearly: return 20
        case lifetime: return 30
        default: return 999
        }
    }
}

enum EntitlementRefreshMode: Equatable {
    /// 起動時・復帰時など。空なら「不明」とみなし、プレミアム→freeへの降格はしない
    case startupCautious
    /// ユーザー操作（設定画面の「復元」や購入直後）。結果を強く信じる。空ならfreeに落としてよい（ストア正常が前提）
    case userInitiated
    /// デバッグ/リカバリ。とにかく現状を強制反映（危険）
    case force
}

enum UsageLimit {
    static let freePerDay = 10
    static let lifetimePerMonth = 200
}

// 日付キー生成は「locale/timezoneのブレ」を消す（地雷：端末設定差で日付キーがズレる）
enum UsageKey {
    private static func formatter(dateFormat: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = dateFormat
        return f
    }

    static func dayKey(_ date: Date = .now) -> String {
        formatter(dateFormat: "yyyy-MM-dd").string(from: date)
    }

    static func monthKey(_ date: Date = .now) -> String {
        formatter(dateFormat: "yyyy-MM").string(from: date)
    }
}

final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var plan: Plan = .free
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    /// true になるまでゲート判定しない（誤爆防止）
    @Published private(set) var entitlementsLoaded = false

    private var ownedProductIDs: Set<String> = []
    private var updatesTask: Task<Void, Never>?
    private var isRefreshingEntitlements = false
    private var pendingEntitlementsRefresh = false

    private let log = Logger(subsystem: "GokigenNote", category: "PremiumManager")

    // start多重呼び出し防止（地雷：updates監視が複数走る）
    private var hasStarted = false
    /// ユーザーごとにキャッシュを分離（ログアウト時に他ユーザーの課金状態が残らないようにする）
    private var currentUserId: String?

    private var planCacheKey: String {
        "PremiumManager.lastPlan.\(currentUserId ?? "guest")"
    }

    /// サーバー sync 成功時の状態。通信失敗時はこれで表示を維持（premium→free の誤り防止）
    private var lastKnownServerPlanKey: String {
        "PremiumManager.lastKnownServerPlan.\(currentUserId ?? "guest")"
    }
    private var lastKnownServerOwnedKey: String {
        "PremiumManager.lastKnownServerOwned.\(currentUserId ?? "guest")"
    }

    private init() {}

    /// 認証状態に応じて呼び出す（ログイン/ログアウト時）。キャッシュをユーザー単位で切り替え、ログアウト時は状態をリセット
    @MainActor
    func setCurrentUserId(_ id: String?) {
        guard currentUserId != id else { return }
        currentUserId = id
        if id != nil {
            if let raw = UserDefaults.standard.string(forKey: planCacheKey),
               let p = Plan.from(cacheValue: raw) {
                plan = p
                entitlementsLoaded = true
            } else {
                plan = .free
                entitlementsLoaded = false
            }
            // 一時: syncEntitlements が呼ばれているか Firebase ログで確認するため1回だけダミー呼び出し
            Task { await Self.debugCallSyncEntitlementsOnce() }
        } else {
            resetForLogout()
        }
    }

    /// 事実確認用: asia-northeast1 の syncEntitlements に届いているか。1回だけ実行。dummy は検証で落ちるが関数ログは出る。
    private static var didRunSyncEntitlementsDebug = false
    private static func debugCallSyncEntitlementsOnce() async {
        guard !didRunSyncEntitlementsDebug else { return }
        didRunSyncEntitlementsDebug = true
        let functions = Functions.functions(region: "asia-northeast1")
        let callable = functions.httpsCallable("syncEntitlements")
        do {
            let result = try await callable.call(["transactions": ["dummy"]])
            print("[syncEntitlements debug] result:", String(describing: result.data))
        } catch {
            print("[syncEntitlements debug] error:", error)
        }
    }

    /// ログアウト時：他ユーザーに課金状態が引き継がれないようにする
    @MainActor
    private func resetForLogout() {
        ownedProductIDs = []
        plan = .free
        entitlementsLoaded = false
    }

    /// App起動時に1回だけ呼ぶ想定
    @MainActor
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if let cached = UserDefaults.standard.string(forKey: planCacheKey),
           let restored = Plan.from(cacheValue: cached) {
            plan = restored
            entitlementsLoaded = true
        }

        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }

        Task {
            await loadProducts()
            // 起動時に必ず refresh。JWS があればサーバー sync し、サーバー結果で plan を上書き（サーバーを正とする）
            await refreshEntitlements(mode: .startupCautious)
        }
    }

    // MARK: - Products

    @MainActor
    func loadProducts() async {
        lastError = nil
        do {
            let ids = Array(ProductID.all)
            log.info("loadProducts bundleId=\(Bundle.main.bundleIdentifier ?? "nil", privacy: .public)")
            log.info("loadProducts ids=\(ids.joined(separator: ","), privacy: .public)")

            let storeProducts = try await Product.products(for: ids)

            log.info("loadProducts resultCount=\(storeProducts.count, privacy: .public)")
            log.info("loadProducts resultIds=\(storeProducts.map { $0.id }.joined(separator: ","), privacy: .public)")
            self.availableProducts = storeProducts
        } catch {
            let msg = String(describing: error)
            self.lastError = "loadProducts failed: \(msg)"
            log.error("loadProducts failed: \(msg, privacy: .public)")
            self.availableProducts = []
        }
    }

    // MARK: - Purchase / Restore

    @MainActor
    func purchase(_ product: Product) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction: StoreKit.Transaction = try Self.verifyTransaction(verification)
                await transaction.finish()
                do {
                    try await AppStore.sync()
                    log.info("AppStore.sync after purchase ok")
                } catch {
                    log.error("AppStore.sync after purchase failed: \(error.localizedDescription, privacy: .public)")
                }
                await refreshEntitlements(mode: .userInitiated)

            case .userCancelled:
                break

            case .pending:
                lastError = "購入が保留中です。承認後に反映されます。"

            @unknown default:
                lastError = "購入処理で不明な状態になりました。"
            }
        } catch {
            lastError = "購入に失敗しました: \(error.localizedDescription)"
            log.error("purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func restore() async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements(mode: .userInitiated)
            log.info("restore: sync+refresh done")
        } catch {
            lastError = "復元に失敗しました: \(error.localizedDescription)"
            log.error("restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Entitlements

    /// 今回の newOwned を適用してよいか。空＝即freeはNG。store正常時だけダウングレード許可。
    @MainActor
    private func shouldApplyEntitlementsResult(
        newOwned: Set<String>,
        mode: EntitlementRefreshMode,
        entitlementsLooksHealthy: Bool,
        now: Date
    ) -> Bool {
        if !newOwned.isEmpty { return true }
        if mode == .force { return true }
        if mode == .userInitiated {
            return entitlementsLooksHealthy
        }
        if mode == .startupCautious {
            if plan.isPremium { return false }
            return entitlementsLooksHealthy
        }
        return false
    }

    /// 現在の権利状態を再計算して plan を確定（二重起動防止）。
    /// updates 連打でも最後まで必ず反映する。
    @MainActor
    func refreshEntitlements(
        mode: EntitlementRefreshMode = .startupCautious,
        now: Date = .now
    ) async {
        if isRefreshingEntitlements {
            pendingEntitlementsRefresh = true
            return
        }
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        while true {
            pendingEntitlementsRefresh = false

            let cached = Plan.from(cacheValue: UserDefaults.standard.string(forKey: planCacheKey) ?? "") ?? .free
            log.debug("refreshEntitlements start mode=\(String(describing: mode), privacy: .public) cached=\(cached.cacheValue, privacy: .public) current=\(self.plan.cacheValue, privacy: .public) products=\(self.availableProducts.count, privacy: .public) loaded=\(self.entitlementsLoaded, privacy: .public)")

            var newOwned: Set<String> = []
            var jwsList: [String] = []
            var verifyFailedCount = 0

            for await result in StoreKit.Transaction.currentEntitlements {
                do {
                    let t: StoreKit.Transaction = try Self.verifyTransaction(result)
                    if t.revocationDate != nil { continue }
                    if let exp = t.expirationDate, exp <= now { continue }
                    newOwned.insert(t.productID)
                    jwsList.append(result.jwsRepresentation)
                } catch {
                    verifyFailedCount += 1
                    log.error("verify failed in currentEntitlements: \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }

            log.info("JWS count: \(jwsList.count, privacy: .public)")

            // サーバーを正とする：JWS があれば sync し、成功時はサーバー結果でローカルを上書き
            if !jwsList.isEmpty {
                let didApplyServer = await syncEntitlementsToServer(transactions: jwsList)
                if didApplyServer {
                    entitlementsLoaded = true
                    log.info("PLAN: \(self.plan.cacheValue, privacy: .public) OWNED: \(Array(self.ownedProductIDs).sorted().joined(separator: ","), privacy: .public) MODE: server_applied")
                    if pendingEntitlementsRefresh {
                        log.debug("pendingEntitlementsRefresh -> rerun once")
                        continue
                    }
                    break
                }
            } else {
                log.info("JWS count: 0 reason: server_sync_skipped (no jwsRepresentation or no entitlements)")
            }

            // サーバー未適用時：最後に成功したサーバー状態を使う（通信失敗で premium→free にならないように）
            if let lastPlanRaw = UserDefaults.standard.string(forKey: lastKnownServerPlanKey),
               let lastPlan = Plan.from(cacheValue: lastPlanRaw) {
                let lastOwnedRaw = UserDefaults.standard.string(forKey: lastKnownServerOwnedKey) ?? ""
                let lastOwned = lastOwnedRaw.isEmpty ? Set<String>() : Set(lastOwnedRaw.split(separator: ",").map { String($0) })
                plan = lastPlan
                ownedProductIDs = lastOwned
                UserDefaults.standard.set(lastPlan.cacheValue, forKey: planCacheKey)
                entitlementsLoaded = true
                log.info("PLAN: \(self.plan.cacheValue, privacy: .public) OWNED: lastKnownServer fallback count=\(lastOwned.count, privacy: .public)")
                if pendingEntitlementsRefresh {
                    log.debug("pendingEntitlementsRefresh -> rerun once")
                    continue
                }
                break
            }

            let entitlementsLooksHealthy =
                verifyFailedCount == 0 &&
                lastError == nil &&
                (!availableProducts.isEmpty || mode == .userInitiated)

            let canApply = shouldApplyEntitlementsResult(
                newOwned: newOwned,
                mode: mode,
                entitlementsLooksHealthy: entitlementsLooksHealthy,
                now: now
            )

            entitlementsLoaded = true

            if canApply {
                let old = plan
                ownedProductIDs = newOwned
                plan = resolvePlan(from: newOwned)
                UserDefaults.standard.set(plan.cacheValue, forKey: planCacheKey)
                if old.cacheValue != self.plan.cacheValue {
                    log.info("plan changed: \(old.cacheValue, privacy: .public) -> \(self.plan.cacheValue, privacy: .public)")
                }
            } else {
                log.info("refreshEntitlements skipped apply. mode=\(String(describing: mode), privacy: .public) newOwnedEmpty=\(newOwned.isEmpty, privacy: .public) healthy=\(entitlementsLooksHealthy, privacy: .public)")
            }

            log.info("PLAN: \(self.plan.cacheValue, privacy: .public) OWNED: \(Array(self.ownedProductIDs).sorted().joined(separator: ","), privacy: .public) MODE: \(String(describing: mode), privacy: .public) HEALTHY: \(entitlementsLooksHealthy, privacy: .public) APPLIED: \(canApply, privacy: .public)")

            if pendingEntitlementsRefresh {
                log.debug("pendingEntitlementsRefresh -> rerun once")
                continue
            }
            break
        }
    }

    private static func verifyTransaction<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }

    /// P1A: Functions syncEntitlements に JWS を送り、サーバで署名検証・entitlements/current に保存。
    /// サーバーを正とする：ok: true のときサーバーの plan / ownedProductIDs でローカルを上書きする。
    /// - Returns: サーバー結果をローカルに適用したか（ok: true かつ plan パース成功時 true）
    private func syncEntitlementsToServer(transactions: [String]) async -> Bool {
        guard !transactions.isEmpty else { return false }
        let functions = Functions.functions(region: "asia-northeast1")
        let callable = functions.httpsCallable("syncEntitlements")
        do {
            let result = try await callable.call(["transactions": transactions])
            guard let data = result.data as? [String: Any] else {
                await MainActor.run { lastError = "プレミアム反映に失敗しました。復元をお試しください。" }
                return false
            }
            let reason = data["reason"] as? String ?? "?"
            let verifiedJwsCount = data["verifiedJwsCount"] as? Int ?? -1
            let acceptedCount = data["acceptedCount"] as? Int ?? -1
            let activeCount = data["activeCount"] as? Int ?? -1
            let effectiveUntil = data["effectiveUntil"] as? NSNumber
            let syncMsg = "syncEntitlements response ok=\(data["ok"] as? Bool ?? false) plan=\(data["plan"] as? String ?? "?") reason=\(reason) verifiedJwsCount=\(verifiedJwsCount) acceptedCount=\(acceptedCount) activeCount=\(activeCount) effectiveUntil=\(effectiveUntil?.stringValue ?? "null")"
            log.info("\(syncMsg, privacy: .public)")
            guard (data["ok"] as? Bool) == true else {
                await MainActor.run { lastError = "プレミアム反映に失敗しました。復元をお試しください。" }
                return false
            }
            await MainActor.run { lastError = nil }
            guard let planStr = data["plan"] as? String, let serverPlan = Plan.from(serverValue: planStr) else {
                log.info("syncEntitlements ok but plan parse failed: \(data["plan"] as? String ?? "?", privacy: .public)")
                return false
            }
            let serverOwned = Set((data["ownedProductIDs"] as? [String]) ?? [])
            plan = serverPlan
            ownedProductIDs = serverOwned
            UserDefaults.standard.set(serverPlan.cacheValue, forKey: planCacheKey)
            UserDefaults.standard.set(serverPlan.cacheValue, forKey: lastKnownServerPlanKey)
            UserDefaults.standard.set(Array(serverOwned).sorted().joined(separator: ","), forKey: lastKnownServerOwnedKey)
            log.info("syncEntitlements applied server plan=\(serverPlan.cacheValue, privacy: .public) owned=\(serverOwned.count, privacy: .public)")
            return true
        } catch {
            log.debug("syncEntitlements failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 優先順位：lifetime > yearly > monthly > fallback（未知のサブスクIDでもサブスク扱い）。App Store側変更に耐える
    private func resolvePlan(from owned: Set<String>) -> Plan {
        if owned.contains(ProductID.lifetime) {
            return .lifetime
        }
        if owned.contains(ProductID.premiumYearly) {
            return .subscription(.yearly)
        }
        if owned.contains(ProductID.premiumMonthly) {
            return .subscription(.monthly)
        }
        if owned.contains(where: { ProductID.subscriptionType(for: $0) != nil }) {
            return .subscription(.monthly)
        }
        return .free
    }

    // MARK: - Updates

    /// Transaction更新を監視（復元・端末間同期・ファミリー共有・返金で必須）
    private func observeTransactionUpdates() async {
        for await update in StoreKit.Transaction.updates {
            do {
                let t: StoreKit.Transaction = try Self.verifyTransaction(update)
                await t.finish()
                await refreshEntitlements(mode: .force)
            } catch {
                log.error("verify failed (updates): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
    }

}

// MARK: - Common Quota (共通枠：言い換え/共感生成の合算)
extension PremiumManager {
    /// 未ロード時の暫定判定用（UserDefaults キャッシュ）
    var cachedPlan: Plan {
        guard let raw = UserDefaults.standard.string(forKey: planCacheKey),
              let p = Plan.from(cacheValue: raw) else { return .free }
        return p
    }

    /// ゲート・表示ともこの plan 基準（未ロード時は cachedPlan）
    var effectivePlan: Plan {
        entitlementsLoaded ? plan : cachedPlan
    }

    private var defaults: UserDefaults { .standard }

    private func dayQuotaKey(_ date: Date = .now) -> String {
        "quota.rewrite.day.\(UsageKey.dayKey(date))"
    }

    private func monthQuotaKey(_ date: Date = .now) -> String {
        "quota.rewrite.month.\(UsageKey.monthKey(date))"
    }

    /// 共通枠（言い換え/共感生成の合算）を使えるか。plan 単一の真実
    func canConsumeRewriteQuota(now: Date = .now) -> Bool {
        guard entitlementsLoaded else { return true }
        let p = plan
        guard let limit = p.rewriteLimit else { return true }

        switch p {
        case .free:
            let used = defaults.integer(forKey: dayQuotaKey(now))
            return used < limit
        case .lifetime:
            let used = defaults.integer(forKey: monthQuotaKey(now))
            return used < limit
        case .subscription:
            return true
        }
    }

    /// 共通枠を1消費（生成開始で呼ぶ）。effectivePlan 基準
    func consumeRewriteQuota(now: Date = .now) {
        guard canConsumeRewriteQuota(now: now) else { return }

        let p = effectivePlan
        switch p {
        case .subscription:
            return
        case .free:
            let key = dayQuotaKey(now)
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        case .lifetime:
            let key = monthQuotaKey(now)
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        }
    }

    /// 表示用（共通枠の残り）。plan 単一の真実
    var remainingRewriteQuotaText: String {
        let p = plan
        guard let limit = p.rewriteLimit else { return "無制限" }

        switch p {
        case .free:
            let used = defaults.integer(forKey: dayQuotaKey())
            let left = max(0, limit - used)
            return "本日あと\(left)回"
        case .lifetime:
            let used = defaults.integer(forKey: monthQuotaKey())
            let left = max(0, limit - used)
            return "今月あと\(left)回"
        case .subscription:
            return "無制限"
        }
    }
}
