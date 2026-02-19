//
//  PremiumManager.swift
//  GokigenNote
//
//  課金状態と使用回数制限を一箇所で管理。
//  共通枠（rewriteQuota）で言い換え・共感を合算。
//

import Foundation
import StoreKit

enum Plan: Equatable {
    case free
    case premium       // サブスク（例: 月額）
    case lifetime      // 買い切り（期限なし、ただし回数制限はあり得る）
}

enum ProductID {
    static let premiumMonthly = "gokigen.premium.monthly"
    static let lifetime = "gokigen.lifetime"
    static let all: Set<String> = [premiumMonthly, lifetime]
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

@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var plan: Plan = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    private var ownedProductIDs: Set<String> = []
    private var updatesTask: Task<Void, Never>?

    // start多重呼び出し防止（地雷：updates監視が複数走る）
    private var hasStarted = false

    private init() {}

    /// App起動時に1回だけ呼ぶ想定
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        updatesTask?.cancel()
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.observeTransactionUpdates()
        }

        Task { @MainActor in
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Array(ProductID.all))
            // 表示順だけ安定化
            self.products = storeProducts.sorted { $0.id < $1.id }
        } catch {
            self.lastError = "商品情報の取得に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase / Restore

    func purchase(_ product: Product) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                // 先に finish（地雷：finishしないと updates が残る/状態が揺れる）
                await transaction.finish()
                // 直後に entitlements 再評価（地雷：買ったのに反映されない）
                await refreshEntitlements()

            case .userCancelled:
                break

            case .pending:
                lastError = "購入が保留中です。承認後に反映されます。"

            @unknown default:
                lastError = "購入処理で不明な状態になりました。"
            }
        } catch {
            lastError = "購入に失敗しました: \(error.localizedDescription)"
        }
    }

    func restore() async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "復元に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// 現在の権利状態を再計算して plan を確定
    func refreshEntitlements(now: Date = .now) async {
        // refreshで lastError を毎回消すと、表示中のエラーが消えてUXが揺れるので消さない（必要なら呼び出し側で消す）
        var newOwned: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let t = try verify(result)

                // 取り消し（返金・取り消し）されていたら無効
                if t.revocationDate != nil { continue }

                // サブスクの期限切れ地雷潰し：
                // currentEntitlements は基本「有効な権利」だが、保険で expirationDate を見る
                if let exp = t.expirationDate, exp <= now {
                    continue
                }

                newOwned.insert(t.productID)
            } catch {
                continue
            }
        }

        ownedProductIDs = newOwned
        plan = resolvePlan(from: newOwned)
    }

    /// 優先順位：lifetime > premium > free（地雷：両方持ってるテスト状態で premium に負ける）
    private func resolvePlan(from owned: Set<String>) -> Plan {
        if owned.contains(ProductID.lifetime) { return .lifetime }
        if owned.contains(ProductID.premiumMonthly) { return .premium }
        return .free
    }

    // MARK: - Updates

    /// Transaction更新を監視（復元・端末間同期・ファミリー共有・返金で必須）
    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            do {
                let t = try verify(update)
                await t.finish()
                await MainActor.run {
                    Task { @MainActor in
                        await self.refreshEntitlements()
                    }
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Verification

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}

// MARK: - Common Quota (共通枠：言い換え/共感生成の合算)
extension PremiumManager {
    private var defaults: UserDefaults { .standard }

    private func dayQuotaKey(_ date: Date = .now) -> String {
        "quota.rewrite.day.\(UsageKey.dayKey(date))"
    }

    private func monthQuotaKey(_ date: Date = .now) -> String {
        "quota.rewrite.month.\(UsageKey.monthKey(date))"
    }

    /// 共通枠（言い換え/共感生成の合算）を使えるか
    func canConsumeRewriteQuota(now: Date = .now) -> Bool {
        switch plan {
        case .premium:
            return true

        case .free:
            let used = defaults.integer(forKey: dayQuotaKey(now))
            return used < UsageLimit.freePerDay

        case .lifetime:
            let used = defaults.integer(forKey: monthQuotaKey(now))
            return used < UsageLimit.lifetimePerMonth
        }
    }

    /// 共通枠を1消費（生成開始で呼ぶ）
    /// ※呼び出し側で canConsumeRewriteQuota を先に通す前提（ここでも保険でガード）
    func consumeRewriteQuota(now: Date = .now) {
        guard canConsumeRewriteQuota(now: now) else { return }

        switch plan {
        case .premium:
            return

        case .free:
            let key = dayQuotaKey(now)
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)

        case .lifetime:
            let key = monthQuotaKey(now)
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        }
    }

    /// 表示用（共通枠の残り）
    var remainingRewriteQuotaText: String {
        switch plan {
        case .premium:
            return "無制限"

        case .free:
            let used = defaults.integer(forKey: dayQuotaKey())
            let left = max(0, UsageLimit.freePerDay - used)
            return "本日あと\(left)回"

        case .lifetime:
            let used = defaults.integer(forKey: monthQuotaKey())
            let left = max(0, UsageLimit.lifetimePerMonth - used)
            return "今月あと\(left)回"
        }
    }
}
