//
//  GokigenViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import Combine
@preconcurrency import Dispatch
import FirebaseFirestore
import Foundation
import SwiftUI

final class GokigenViewModel: ObservableObject {
    @Published var selectedMood: Mood = .neutral
    @Published var draftText: String = ""

    /// 保存前に uid を取る用（AuthGate を通す）
    weak var authViewModel: AuthViewModel?

    /// 直近の入力が音声か（保存時の inputMethod 用）
    private var lastInputWasVoice = false

    // MARK: - DraftSession（編集中1件・同一 doc に upsert）

    @Published private(set) var draftSession: DraftSession?
    @Published private(set) var autoSaveState: AutoSaveState = .idle
    private var draftEntryId: String? { draftSession?.id }
    /// 確定処理中の entryId（この id への upsert は行わない）
    private var finalizingDraftId: String?

    private func startDraftIfNeeded(rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if draftSession == nil {
            draftSession = DraftSession(
                id: UUID().uuidString,
                rawText: trimmed,
                scene: selectedScene.rawValue,
                inputMethod: lastInputWasVoice ? "voice" : "text",
                moodRaw: String(selectedMood.rawValue)
            )
        }
    }

    private func resetDraft() {
        draftSession = nil
        autoSaveState = .idle
        lastSaveError = nil
        lastInputWasVoice = false
        draftText = ""
        reformulatedText = ""
        empathyDraft = ""
        nextStepDraft = ""
    }

    /// 自動保存中か（記録ボタン無効化用）
    var isAutoSaving: Bool {
        if case .saving = autoSaveState { return true }
        return false
    }

    /// 自動保存失敗時の再送（同 entryId に upsert で冪等）
    func retryAutoSave() {
        let raw = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rewrite = reformulatedText
        guard !raw.isEmpty else { return }
        saveEntryAfterReformulateSuccess(rawText: raw, rewriteText: rewrite)
    }

    /// DraftSession を唯一の真実として EntryPayload を組む（UIから剥がす）
    private func makePayloadFromDraft(_ s: DraftSession, now: Date = .now) -> EntryPayload {
        var client: [String: Any] = ["platform": "iOS"]
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            client["appVersion"] = v
        }
        return EntryPayload(
            entryId: s.id,
            dateKey: FirestoreService.dayKey(from: s.createdAtLocal),
            scene: s.scene,
            inputMethod: s.inputMethod,
            rawText: s.rawText,
            rewriteText: s.rewriteText.isEmpty ? nil : s.rewriteText,
            empathyText: s.empathyText.isEmpty ? nil : s.empathyText,
            moodRaw: s.moodRaw.isEmpty ? nil : s.moodRaw,
            nextStep: s.nextStep.isEmpty ? nil : s.nextStep,
            promptMeta: nil,
            model: nil,
            usage: nil,
            client: client
        )
    }

    /// 音声認識結果を入力欄に反映（話す → 整理される の入口）
    func applySpeechInput(_ text: String) {
        draftText = text
        lastInputWasVoice = true
    }

    /// 結果を隠して入力からやり直す（もう一度調整）
    func clearReformulatedResult() {
        reformulatedText = ""
    }
    @Published var reformulationPurpose: ReformulationPurpose = .shareFeeling
    @Published var reformulationAudience: ReformulationAudience = .colleague
    @Published var reformulationTone: ReformulationTone = .soft
    @Published var selectedScene: ReformulationScene = .work
    @Published var currentPrompt: String
    @Published private(set) var empathyDraft: String = ""
    @Published private(set) var nextStepDraft: String = ""
    @Published private(set) var reformulatedText: String = ""
    @Published private(set) var entries: [Entry] = []
    @Published var lastSuccessMessage: String?
    @Published var lastErrorMessage: String?
    @Published private(set) var lastSaveError: String?
    @Published private(set) var isLoadingEmpathy: Bool = false
    @Published private(set) var isLoadingReformulation: Bool = false
    @Published private(set) var isLoadingEntries: Bool = false
    @Published private(set) var canLoadMore: Bool = true
    @Published private(set) var isSyncing: Bool = false
    /// 無料ユーザー連打制限: クールダウン終了時刻（nil または 過ぎていればボタン有効）
    @Published var reformulateCooldownEndAt: Date?

    /// 同一入力あたり再生成2回まで（無料UX）
    private var lastReformulateInputText: String?
    private var regenerateCountForCurrentInput: Int = 0

    /// 混雑モーダル「再試行」用。RetryBus.reformulate で retryReformulateIfPossible が呼ばれる
    private struct PendingReformulate {
        let text: String
        let context: ReformulationContext
        let draftEntryId: String?
        let cacheKey: String
    }
    private var pendingReformulate: PendingReformulate?
    private var retryObserver: NSObjectProtocol?

    /// defer 用。MainActor で後から実行したい処理を同期クロージャで渡す（defer の async 推論を防ぐ）。
    private nonisolated func runOnMainActorLater(_ body: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                body()
            }
        }
    }

    /// 同期メソッドにし、addObserver の using: に渡すクロージャを非同期推論されないようにする。
    private func handleRetryRequested(_ note: Notification) {
        guard let action = RetryBus.parseAction(note), action == .reformulate else { return }
        Task { await self.retryReformulateIfPossible() }
    }

    @MainActor
    init() {
        self.currentPrompt = PromptProvider.random()
        self.entries = []
        self.retryObserver = NotificationCenter.default.addObserver(
            forName: RetryBus.retryRequested,
            object: nil,
            queue: .main,
            using: { [weak self] note in
                self?.handleRetryRequested(note)
            }
        )
    }

    deinit {
        if let o = retryObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    private enum Copy {
        static let saveSuccess = "あなたの今が書き留められたよ。"
        static let emptyDraft = "まず一言だけ書いてみませんか？"
        static let offlineFallback = "今は手元のアイデアで続けるね。"
        static let reformulationError = "言い換えに失敗しました。もう一度お試しください。"
        static let dailyLimitReached = "本日の利用回数に達したため、簡易表示しています。"
        static let fallbackReformulation = "通信のため簡易表示しています。"
        static let reformulateRegenerateLimit = "この文章の再生成は2回までです。"
        /// resource-exhausted / not-found / internal などサーバ要因は全てこの1文に統一
        static let congestionMessage = "混雑中です。少し待つか、優先でチェックできます。"
    }

    /// 1日あたりの Gemini API 呼び出し上限（Phase 2）
    private static let dailyAPICallLimit = 30
    /// 言い換えキャッシュの最大件数（Phase 1）
    private static let reformulationCacheMaxCount = 50
    /// 同一入力＋同一コンテキストで1分以内は完全キャッシュ（連打ユーザーでコスト削減）
    private static let reformulationCacheTTLSeconds: TimeInterval = 60
    /// メモリに保持する entries の上限（無制限成長によるメモリキル防止）
    private static let maxEntriesInMemory = 300
    /// UserDefaults に保存する件数（起動時の読み込み負荷軽減）
    private static let maxEntriesToCache = 200

    private struct ReformulationCacheEntry {
        let value: String
        let createdAt: Date
    }
    private var reformulationCache: [String: ReformulationCacheEntry] = [:]
    private var reformulationCacheOrder: [String] = []
    private var hasShownFirstReformulationSuccess = false

    // “古いレスポンスがUIを上書き”防止用
    private var empathyRequestID: UUID?
    private var reformulationRequestID: UUID?

    // 同時実行防止（共通枠）
    private var aiLock = false

    private struct AIRequestToken {
        let id: UUID
        let kind: Kind
        enum Kind { case empathy, reformulation }
    }

    @MainActor
    private func beginAIRequest(kind: AIRequestToken.Kind) -> AIRequestToken? {
        if aiLock { return nil }
        if isLoadingEmpathy || isLoadingReformulation { return nil }

        aiLock = true
        let token = AIRequestToken(id: UUID(), kind: kind)

        switch kind {
        case .empathy:
            empathyRequestID = token.id
            isLoadingEmpathy = true
        case .reformulation:
            reformulationRequestID = token.id
            isLoadingReformulation = true
        }
        return token
    }

    @MainActor
    private func endAIRequest(_ token: AIRequestToken) {
        defer { aiLock = false }

        switch token.kind {
        case .empathy:
            if empathyRequestID == token.id {
                empathyRequestID = nil
                isLoadingEmpathy = false
            }
        case .reformulation:
            if reformulationRequestID == token.id {
                reformulationRequestID = nil
                isLoadingReformulation = false
            }
        }
    }

    /// ここでは “消費しない”。不足なら Paywall。未ロード時は仮許可（UX優先）
    @MainActor
    private func ensureQuotaOrOpenPaywall() -> Bool {
        let pm = PremiumManager.shared

        if !pm.entitlementsLoaded {
            return true
        }

        guard pm.canConsumeRewriteQuota() else {
            publishError(message: "回数上限に達しました（\(pm.remainingRewriteQuotaText)）。プレミアムで無制限にできます。")
            PaywallCoordinator.shared.present()
            return false
        }
        return true
    }

    /// 実際にGeminiを叩く直前にだけ消費
    @MainActor
    private func consumeQuota() {
        PremiumManager.shared.consumeRewriteQuota()
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func canCallGeminiAPI(now: Date = .now) -> Bool {
        let keyDate = "GeminiAPIDailyDate"
        let keyCount = "GeminiAPIDailyCount"
        let today = Self.dateString(now)

        if UserDefaults.standard.string(forKey: keyDate) != today {
            UserDefaults.standard.set(today, forKey: keyDate)
            UserDefaults.standard.set(0, forKey: keyCount)
        }
        let count = UserDefaults.standard.integer(forKey: keyCount)
        return count < Self.dailyAPICallLimit
    }

    private func recordGeminiAPICall(now: Date = .now) {
        let keyDate = "GeminiAPIDailyDate"
        let keyCount = "GeminiAPIDailyCount"
        let today = Self.dateString(now)

        if UserDefaults.standard.string(forKey: keyDate) != today {
            UserDefaults.standard.set(today, forKey: keyDate)
            UserDefaults.standard.set(0, forKey: keyCount)
        }
        let count = UserDefaults.standard.integer(forKey: keyCount)
        UserDefaults.standard.set(count + 1, forKey: keyCount)
    }

    /// 目的・相手・トーン・場面を含むキャッシュキー（同じ入力でもコンテキストで別結果）
    private func reformulationCacheKey(trimmed: String) -> String {
        "\(trimmed)|\(reformulationPurpose.rawValue)|\(reformulationAudience.rawValue)|\(reformulationTone.rawValue)|\(selectedScene.rawValue)"
    }

    /// 言い換え結果をキャッシュに追加（最大件数で古いものを削除・TTL 1分）
    private func setReformulationCache(cacheKey: String, result: String) {
        if reformulationCacheOrder.count >= Self.reformulationCacheMaxCount,
            let first = reformulationCacheOrder.first
        {
            reformulationCacheOrder.removeFirst()
            reformulationCache.removeValue(forKey: first)
        }
        if !reformulationCacheOrder.contains(cacheKey) {
            reformulationCacheOrder.append(cacheKey)
        }
        reformulationCache[cacheKey] = ReformulationCacheEntry(value: result, createdAt: Date())
    }

    /// キャッシュ取得。1分以内のエントリのみ有効（超過は未ヒット扱い・エントリ削除）
    private func getReformulationCache(cacheKey: String, now: Date = Date()) -> String? {
        guard let entry = reformulationCache[cacheKey] else { return nil }
        if now.timeIntervalSince(entry.createdAt) > Self.reformulationCacheTTLSeconds {
            reformulationCache.removeValue(forKey: cacheKey)
            reformulationCacheOrder.removeAll { $0 == cacheKey }
            return nil
        }
        return entry.value
    }

    private let persistence = Persistence.shared
    private let geminiService = GeminiService()
    private let firestoreService = FirestoreService.shared
    private var currentUserId: String?
    private var lastEntryDoc: DocumentSnapshot?
    private var lastLoadMoreAt: Date = .distantPast
    private var isFlushingPending = false
    private var lastGeminiSuccess: (text: String, response: EmpathyResponse)?
    private var lastGeminiRequest: String?
    private let micExamples: [Mood: [String]] = [
        .veryHappy: [
            "今日は嬉しいことが続いて笑顔で過ごせた。",
            "頑張ったぶん褒めてもらえて、心がふわっと温かくなった。",
        ],
        .happy: [
            "ちょっとした会話が楽しくて気持ちが軽くなった。",
            "好きな音楽を聴いたら自然と前向きになれた。",
        ],
        .neutral: [
            "特別な出来事はなかったけれど穏やかだった。",
            "いつものペースで進められて少し安心した。",
        ],
        .sad: [
            "思っていたより疲れが残っていて少し落ち込んだ。",
            "自分の気持ちをうまく伝えられず、もどかしい。",
        ],
        .verySad: [
            "ずっと心がざわついていて、深呼吸を忘れていたかも。",
            "エネルギーが出ず、誰かに頼りたい気持ちが強かった。",
        ],
    ]

    func setUserId(_ userId: String) {
        guard currentUserId != userId else { return }
        currentUserId = userId

        // ① ローカル先出し（即表示）。件数上限でメモリを抑える
        let cached = persistence.loadEntries(userId: userId)
        self.entries = trimEntriesToLimit(cached.sorted { $0.date > $1.date })

        // ② pending 再送（先に実行）
        flushPending()

        // ③ 裏で Firestore 初回ページ同期
        loadInitial(userId: userId)
    }

    /// ログアウト時など。前ユーザー参照が残らないように必ず呼ぶ。
    func clearUserId() {
        guard currentUserId != nil else { return }
        currentUserId = nil
        entries = []
    }

    /// Firestore 保存失敗時に pending に積む
    private func enqueuePending(_ id: UUID, userId: String) {
        persistence.addPendingEntryId(id, userId: userId)
    }

    /// 成功したら pending から消す（以前の失敗が残ってても即回収）
    private func dequeuePending(_ id: UUID, userId: String) {
        persistence.removePendingEntryId(id, userId: userId)
    }

    /// 未同期キューを再送。失敗したら break。entries に無い id は削除（ゴミ掃除）。多重実行ガードあり。
    @MainActor
    func flushPending() {
        guard let uid = currentUserId else { return }
        guard !isFlushingPending else { return }
        isFlushingPending = true

        Task {
            defer { runOnMainActorLater { [weak self] in self?.isFlushingPending = false } }

            let pending = persistence.loadPendingEntryIds(userId: uid)
            guard !pending.isEmpty else { return }

            let pendingSorted = await MainActor.run {
                pending.sorted { a, b in
                    let ea = self.entries.first(where: { $0.id == a })?.updatedAt ?? .distantPast
                    let eb = self.entries.first(where: { $0.id == b })?.updatedAt ?? .distantPast
                    return ea < eb
                }
            }

            for id in pendingSorted {
                let entry = await MainActor.run {
                    self.entries.first(where: { $0.id == id })
                }

                guard let entry else {
                    persistence.removePendingEntryId(id, userId: uid)
                    continue
                }

                do {
                    try await firestoreService.saveEntry(entry, for: uid)
                    persistence.removePendingEntryId(id, userId: uid)
                } catch {
                    break
                }
            }
        }
    }

    /// Entry の内容が変わったときに必ず呼ぶ。updatedAt を更新し「新しい方が勝つ」マージを保証する。
    private func touch(_ entry: inout Entry) {
        entry.updatedAt = Date()
    }

    /// ローカルとリモートを id でマージ。同じ id は updatedAt が新しい方を採用。オフラインで増えたローカルは残す。
    private func merge(local: [Entry], remote: [Entry]) -> [Entry] {
        var dict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for r in remote {
            if let l = dict[r.id] {
                dict[r.id] = (l.updatedAt >= r.updatedAt) ? l : r
            } else {
                dict[r.id] = r
            }
        }
        let sorted = dict.values.sorted { $0.date > $1.date }
        return Array(sorted.prefix(Self.maxEntriesInMemory))
    }

    /// 配列をメモリ上限件数に切り詰める（日付降順の先頭＝最新を残す）
    private func trimEntriesToLimit(_ list: [Entry]) -> [Entry] {
        Array(list.prefix(Self.maxEntriesInMemory))
    }

    /// Firestore 初回1ページ取得 → マージ → キャッシュ更新
    private func loadInitial(userId: String) {
        lastEntryDoc = nil
        canLoadMore = true
        isSyncing = true

        Task {
            do {
                let result = try await firestoreService.loadEntriesPage(
                    for: userId,
                    limit: 30,
                    startAfter: nil
                )
                await MainActor.run {
                    self.entries = self.merge(local: self.entries, remote: result.entries)
                    self.lastEntryDoc = result.lastDoc
                    self.canLoadMore =
                        !result.entries.isEmpty && result.entries.count == 30
                        && result.lastDoc != nil
                    self.isSyncing = false
                    let toCache = Array(self.entries.prefix(Self.maxEntriesToCache))
                    self.persistence.saveEntries(toCache, userId: userId)
                }
                await MainActor.run {
                    self.flushPending()
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    print("❌ [GokigenViewModel] Firestore初回読み込みエラー: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 追加読み込み（記録タブで末尾表示時に呼ぶ）。連打防止のため 0.7 秒クールダウンあり。
    func loadMore(userId: String? = nil) {
        let uid = userId ?? currentUserId
        guard let uid, !isLoadingEntries, canLoadMore else { return }
        guard Date().timeIntervalSince(lastLoadMoreAt) > 0.7 else { return }

        lastLoadMoreAt = Date()
        isLoadingEntries = true
        Task {
            do {
                let result = try await firestoreService.loadEntriesPage(
                    for: uid,
                    limit: 30,
                    startAfter: lastEntryDoc
                )
                await MainActor.run {
                    let next: [Entry]
                    if lastEntryDoc == nil {
                        next = result.entries.sorted { $0.date > $1.date }
                    } else {
                        next = (self.entries + result.entries).sorted { $0.date > $1.date }
                    }
                    self.entries = self.trimEntriesToLimit(next)
                    self.lastEntryDoc = result.lastDoc
                    self.canLoadMore =
                        !result.entries.isEmpty && result.entries.count == 30
                        && result.lastDoc != nil
                    self.isLoadingEntries = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingEntries = false
                    print("❌ [GokigenViewModel] Firestore読み込みエラー: \(error.localizedDescription)")
                }
            }
        }
    }

    private var isDraftEmpty: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 入力補助

    @MainActor
    func newPrompt() {
        currentPrompt = PromptProvider.random()
    }

    @MainActor
    func insertMicExample() {
        guard isDraftEmpty, let sample = micExamples[selectedMood]?.randomElement() else { return }
        draftText = sample
    }

    // MARK: - 言い換え生成

    @MainActor
    func buildEmpathyDraft(forceRefresh: Bool = false) {
        let trimmed = InputLimit.clampText(draftText, maxChars: InputLimit.empathy)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        // ローカル即時反映
        let local = EmpathyEngine.rewrite(original: trimmed, mood: selectedMood)
        empathyDraft = local.0
        nextStepDraft = local.1

        // キャッシュヒットは0消費
        if !forceRefresh,
            let cache = lastGeminiSuccess,
            cache.text == trimmed
        {
            empathyDraft = cache.response.empathy
            nextStepDraft = cache.response.nextStep
            return
        }

        // 未ログイン時は回数チェック前に止める（P1A）
        guard let authVM = authViewModel else {
            publishError(message: "ログインが必要です。")
            return
        }
        do {
            _ = try AuthGate.requireUID(authVM: authVM)
        } catch {
            publishError(message: "ログインが必要です。")
            return
        }

        // 日次上限は0消費で終了
        guard canCallGeminiAPI() else {
            publishError(message: Copy.dailyLimitReached)
            return
        }

        guard let token = beginAIRequest(kind: .empathy) else { return }
        recordGeminiAPICall()

        lastGeminiRequest = trimmed

        Task { [trimmed, token] in
            defer { runOnMainActorLater { [weak self] in self?.endAIRequest(token) } }

            // P1A: consumeRewrite でサーバが回数制限・消費。allowed なら AI 実行。
            do {
                let draftId = await MainActor.run { self.draftEntryId }
                let quota = try await QuotaService.shared.consumeRewrite(
                    op: .empathy,
                    draftEntryId: draftId
                )

                await MainActor.run {
                    PremiumManager.shared.applyServerQuota(
                        used: quota.used, remaining: quota.remaining, limit: quota.limit,
                        resetKey: quota.resetKey)
                    guard self.empathyRequestID == token.id else { return }
                }

                if !quota.allowed {
                    await MainActor.run {
                        guard self.empathyRequestID == token.id else { return }
                        if let sec = quota.cooldownRemainingSeconds, sec > 0 {
                            self.reformulateCooldownEndAt = Date().addingTimeInterval(
                                TimeInterval(sec))
                            self.publishError(message: "あと\(sec)秒お待ちください")
                        } else if quota.paywall, quota.reason == "quota_exceeded" {
                            PaywallCoordinator.shared.presentQuotaExceeded()
                        } else {
                            self.publishError(message: Copy.congestionMessage)
                            let tier: QueueTier =
                                PremiumManager.shared.effectivePlan.serverPlanValue
                                    == "subscription_yearly" ? .priority : .standard
                            PaywallCoordinator.shared.presentCongestion(
                                tier: tier, retryAfterSeconds: nil, retryAction: .empathy)
                        }
                    }
                    return
                }
            } catch {
                await MainActor.run {
                    guard self.empathyRequestID == token.id else { return }
                    if QuotaService.isUnauthenticated(error) {
                        self.publishError(message: "ログインが必要です。")
                    } else if CongestionGateHandler.presentIfNeeded(
                        error: error, op: .empathy, payloadKey: trimmed)
                    {
                        self.publishError(message: Copy.congestionMessage)
                    } else {
                        self.publishError(message: "回数確認に失敗しました。通信状況を確認してください。")
                    }
                }
                return
            }

            do {
                let response = try await geminiService.generateEmpathy(for: trimmed)
                await MainActor.run {
                    guard self.empathyRequestID == token.id else { return }

                    self.empathyDraft = response.empathy
                    self.nextStepDraft = response.nextStep
                    self.lastGeminiSuccess = (text: trimmed, response: response)
                    self.lastGeminiRequest = nil
                }
            } catch {
                print("[Gemini] ERROR generateEmpathy: \(error)")
                await MainActor.run {
                    guard self.empathyRequestID == token.id else { return }

                    self.publishError(message: Copy.offlineFallback)
                    self.lastGeminiRequest = nil
                }
            }
        }
    }

    @MainActor
    func reformulateText() {
        if PremiumManager.shared.isFreeTrialEnded {
            PaywallCoordinator.shared.present()
            return
        }
        let maxChars = InputLimit.maxCharsReformulate(isPremium: PremiumManager.shared.effectivePlan.isPremium)
        let trimmed = InputLimit.clampText(draftText, maxChars: maxChars)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        startDraftIfNeeded(rawText: trimmed)

        let context = ReformulationContext(
            purpose: reformulationPurpose,
            audience: reformulationAudience,
            tone: reformulationTone,
            scene: selectedScene,
            isYearly: PremiumManager.shared.effectivePlan.isYearly
        )
        let cacheKey = reformulationCacheKey(trimmed: trimmed)

        // キャッシュヒットは0消費（1分TTL）
        if let cached = getReformulationCache(cacheKey: cacheKey) {
            reformulatedText = cached
            return
        }

        // 未ログイン時は回数チェック前に止める（P1A: 課金しても使えない状態を防ぐ）
        guard let authVM = authViewModel else {
            publishError(message: "ログインが必要です。")
            return
        }
        do {
            _ = try AuthGate.requireUID(authVM: authVM)
        } catch {
            publishError(message: "ログインが必要です。")
            return
        }

        // 日次上限は0消費でローカル簡易
        guard canCallGeminiAPI() else {
            reformulatedText = EmpathyEngine.reformulateLocal(original: trimmed)
            publishError(message: Copy.dailyLimitReached)
            return
        }

        // 同一入力あたり再生成は最大2回まで（無料UX・連打防止）
        if trimmed != lastReformulateInputText {
            lastReformulateInputText = trimmed
            regenerateCountForCurrentInput = 0
        }
        regenerateCountForCurrentInput += 1
        if regenerateCountForCurrentInput > 2 {
            publishError(message: Copy.reformulateRegenerateLimit)
            return
        }

        guard let token = beginAIRequest(kind: .reformulation) else {
            publishError(message: "しばらくお待ちください。前の処理が完了してからお試しください。")
            return
        }
        recordGeminiAPICall()

        pendingReformulate = PendingReformulate(
            text: trimmed,
            context: context,
            draftEntryId: draftEntryId,
            cacheKey: cacheKey
        )

        Task { [trimmed, token, context, cacheKey] in
            defer { runOnMainActorLater { [weak self] in self?.endAIRequest(token) } }

            do {
                let draftId = await MainActor.run { self.draftEntryId }
                let quota = try await QuotaService.shared.consumeRewrite(
                    op: .reformulate,
                    draftEntryId: draftId
                )

                await MainActor.run {
                    PremiumManager.shared.applyServerQuota(
                        used: quota.used, remaining: quota.remaining, limit: quota.limit,
                        resetKey: quota.resetKey)
                    guard self.reformulationRequestID == token.id else { return }
                }

                if !quota.allowed {
                    await MainActor.run {
                        guard self.reformulationRequestID == token.id else { return }
                        if let sec = quota.cooldownRemainingSeconds, sec > 0 {
                            self.reformulateCooldownEndAt = Date().addingTimeInterval(
                                TimeInterval(sec))
                            self.publishError(message: "あと\(sec)秒お待ちください")
                        } else if quota.paywall, quota.reason == "quota_exceeded" {
                            PaywallCoordinator.shared.presentQuotaExceeded()
                        } else {
                            self.publishError(message: Copy.congestionMessage)
                            let tier: QueueTier =
                                PremiumManager.shared.effectivePlan.serverPlanValue
                                    == "subscription_yearly" ? .priority : .standard
                            PaywallCoordinator.shared.presentCongestion(
                                tier: tier, retryAfterSeconds: nil, retryAction: .reformulate)
                        }
                    }
                    return
                }
            } catch {
                await MainActor.run {
                    guard self.reformulationRequestID == token.id else { return }
                    if QuotaService.isUnauthenticated(error) {
                        self.publishError(message: "ログインが必要です。")
                    } else if CongestionGateHandler.presentIfNeeded(
                        error: error, op: .reformulate, payloadKey: cacheKey)
                    {
                        self.publishError(message: Copy.congestionMessage)
                    } else {
                        self.publishError(message: "回数確認に失敗しました。通信状況を確認してください。")
                    }
                }
                return
            }

            do {
                try await performReformulate(
                    text: trimmed, context: context, cacheKey: cacheKey, token: token)
            } catch {
                print("[Gemini] ERROR reformulateText: \(error)")
                if FunctionsErrorExtraction.isFreeTrialEnded(error) {
                    await MainActor.run { PaywallCoordinator.shared.present() }
                    return
                }
                await MainActor.run {
                    guard self.reformulationRequestID == token.id else { return }
                    if CongestionGateHandler.presentIfNeeded(
                        error: error, op: .reformulate, payloadKey: cacheKey)
                    {
                        self.publishError(message: Copy.congestionMessage)
                        return
                    }
                    let errorMessage = Copy.congestionMessage
                    let fallback = EmpathyEngine.reformulateLocal(original: trimmed)
                    let textToShow =
                        fallback.isEmpty
                        ? "変換を取得できませんでした。しばらくしてからやり直してください。"
                        : fallback
                    self.reformulatedText = textToShow
                    self.publishError(message: errorMessage)
                    self.saveEntryAfterReformulateSuccess(rawText: trimmed, rewriteText: textToShow)
                }
            }
        }
    }

    /// 空やプレースホルダ（〇〇のみ等）は無効とみなし、失敗扱いにしてフォールバックへ
    private static func isInvalidReformulationResult(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let normalized = t.replacingOccurrences(of: "〇", with: "")
        if normalized.isEmpty { return true }
        return false
    }

    /// 言い換えの実実行（callable 呼び出し＋UI反映）。reformulateText と retryReformulateIfPossible から利用。
    private func performReformulate(
        text: String, context: ReformulationContext, cacheKey: String, token: AIRequestToken
    ) async throws {
        let (reformulated, isFallback, limitsPayload) = try await geminiService.reformulateText(
            for: text, context: context)
        if Self.isInvalidReformulationResult(reformulated) {
            throw NSError(
                domain: "GokigenViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "言い換え結果が取得できませんでした。"])
        }
        await MainActor.run {
            guard self.reformulationRequestID == token.id else { return }
            self.reformulatedText = reformulated
            self.setReformulationCache(cacheKey: cacheKey, result: reformulated)
            if let limits = limitsPayload {
                PremiumManager.shared.applyServerQuotaFromLimits(limits)
            }
            if isFallback {
                self.publishError(message: "通信の都合で入力文をそのまま表示しています。しばらくして再度お試しください。")
            } else if !self.hasShownFirstReformulationSuccess {
                self.hasShownFirstReformulationSuccess = true
                self.lastSuccessMessage = "そのまま使えます"
            }
            self.saveEntryAfterReformulateSuccess(rawText: text, rewriteText: reformulated)
        }
    }

    /// RetryBus.reformulate 受信時に呼ばれる。pending があれば performReformulate を再実行。
    @MainActor
    private func retryReformulateIfPossible() async {
        guard let pending = pendingReformulate else { return }
        guard let token = beginAIRequest(kind: .reformulation) else { return }
        defer { endAIRequest(token) }

        do {
            try await performReformulate(
                text: pending.text, context: pending.context, cacheKey: pending.cacheKey,
                token: token)
        } catch {
            if CongestionGateHandler.presentIfNeeded(
                error: error, op: .reformulate, payloadKey: pending.cacheKey)
            {
                publishError(message: Copy.congestionMessage)
            } else {
                publishError(message: Copy.congestionMessage)
            }
        }
    }

    /// クールダウン終了時に View から呼ぶ（タイマーで1秒ごとなど）
    func clearReformulateCooldownIfNeeded() {
        guard let end = reformulateCooldownEndAt, Date() >= end else { return }
        reformulateCooldownEndAt = nil
    }

    /// 生成成功後に同一 draft doc へ upsert。一覧追加・入力クリアはしない。
    private func saveEntryAfterReformulateSuccess(rawText: String, rewriteText: String) {
        lastSaveError = nil
        guard let authVM = authViewModel else { return }
        let uid: String
        do {
            uid = try AuthGate.requireUID(authVM: authVM)
        } catch {
            return
        }

        startDraftIfNeeded(rawText: rawText)
        guard let draftId = draftEntryId else { return }
        if draftId == finalizingDraftId { return }

        autoSaveState = .saving

        let context = ReformulationContext(
            purpose: reformulationPurpose,
            audience: reformulationAudience,
            tone: reformulationTone,
            scene: selectedScene,
            isYearly: PremiumManager.shared.effectivePlan.isYearly
        )
        var client: [String: Any] = ["platform": "iOS"]
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            client["appVersion"] = v
        }
        let payload = EntryPayload(
            entryId: draftId,
            dateKey: FirestoreService.dayKey(from: Date()),
            scene: selectedScene.rawValue,
            inputMethod: lastInputWasVoice ? "voice" : "text",
            rawText: rawText,
            rewriteText: rewriteText,
            empathyText: empathyDraft.isEmpty ? nil : empathyDraft,
            moodRaw: String(selectedMood.rawValue),
            nextStep: nextStepDraft.isEmpty ? nil : nextStepDraft,
            promptMeta: [
                "purpose": context.purpose.rawValue,
                "audience": context.audience.rawValue,
                "tone": context.tone.rawValue,
            ],
            model: nil,
            usage: nil,
            client: client
        )
        Task {
            do {
                await MainActor.run {
                    if var session = self.draftSession {
                        session.rawText = rawText
                        session.rewriteText = rewriteText
                        session.empathyText = self.empathyDraft
                        session.nextStep = self.nextStepDraft
                        session.scene = self.selectedScene.rawValue
                        session.inputMethod = self.lastInputWasVoice ? "voice" : "text"
                        session.moodRaw = String(self.selectedMood.rawValue)
                        self.draftSession = session
                    }
                }
                try await FirestoreService.shared.upsertEntry(
                    uid: uid, entryId: draftId, payload: payload)
                await MainActor.run {
                    self.autoSaveState = .saved
                    self.lastInputWasVoice = false
                }
            } catch {
                await MainActor.run {
                    self.lastSaveError = error.localizedDescription
                    self.autoSaveState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 保存 / 履歴

    @MainActor
    func saveCurrentEntry() {
        // 記録する直前にテキストだけある場合も draft を用意（言い換え未実行でも保存可能）
        startDraftIfNeeded(rawText: draftText)
        guard let s = draftSession else {
            publishError(message: "下書きがありません")
            return
        }
        let trimmed = s.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        guard let authVM = authViewModel else {
            publishError(message: "サインインが必要です")
            return
        }
        let uid: String
        do {
            uid = try AuthGate.requireUID(authVM: authVM)
        } catch {
            publishError(message: "サインインが必要です")
            return
        }

        if case .saving = autoSaveState {
            publishError(message: "保存中です。少し待ってください。")
            return
        }

        let draftId = s.id
        finalizingDraftId = draftId
        lastSaveError = nil

        // empathy/next が空ならフォールバックして draft に反映（draft を唯一の真実にする）
        if s.empathyText.isEmpty || s.nextStep.isEmpty {
            let mood = Mood(rawValue: Int(s.moodRaw) ?? 0) ?? .neutral
            let (emp, next) = EmpathyEngine.rewrite(original: trimmed, mood: mood)
            if var session = draftSession {
                if session.empathyText.isEmpty { session.empathyText = emp }
                if session.nextStep.isEmpty { session.nextStep = next }
                draftSession = session
            }
        }

        guard let sessionForPayload = draftSession else {
            publishError(message: "下書きがありません")
            return
        }
        let payload = makePayloadFromDraft(sessionForPayload)

        let moodForEntry = Mood(rawValue: Int(sessionForPayload.moodRaw) ?? 0) ?? .neutral
        let finalEntry = Entry(
            id: UUID(uuidString: draftId) ?? UUID(),
            documentId: draftId,
            date: sessionForPayload.createdAtLocal,
            mood: moodForEntry,
            originalText: sessionForPayload.rawText,
            reformulatedText: sessionForPayload.rewriteText.isEmpty
                ? nil : sessionForPayload.rewriteText,
            empathyText: sessionForPayload.empathyText,
            nextStep: sessionForPayload.nextStep
        )

        Task {
            do {
                try await FirestoreService.shared.upsertEntry(
                    uid: uid, entryId: draftId, payload: payload)
                try await FirestoreService.shared.finalizeEntry(uid: uid, entryId: draftId)
                await MainActor.run {
                    withAnimation(.easeInOut) { self.entries.insert(finalEntry, at: 0) }
                    self.persistence.saveEntries(self.entries, userId: uid)
                    self.finalizingDraftId = nil
                    self.resetDraft()
                    self.selectedMood = .neutral
                    self.currentPrompt = PromptProvider.random()
                    self.publishSuccess(message: Copy.saveSuccess)
                }
            } catch {
                await MainActor.run {
                    self.finalizingDraftId = nil
                    self.lastSaveError = error.localizedDescription
                    self.publishError(message: "確定に失敗しました。通信状況を確認してください。")
                }
            }
        }
    }

    @MainActor
    func delete(at offsets: IndexSet) {
        let entriesToDelete = offsets.map { entries[$0] }

        withAnimation(.easeInOut) {
            entries.remove(atOffsets: offsets)
        }
        if let uid = currentUserId {
            persistence.saveEntries(entries, userId: uid)
        } else {
            persistence.save(entries)
        }

        // Firestoreからも削除
        if let userId = currentUserId {
            Task {
                for entry in entriesToDelete {
                    try? await firestoreService.deleteEntry(
                        entryId: entry.documentId ?? entry.id.uuidString, for: userId)
                }
            }
        }
    }

    @MainActor
    func move(from source: IndexSet, to destination: Int) {
        withAnimation(.easeInOut) {
            entries.move(fromOffsets: source, toOffset: destination)
        }
        if let uid = currentUserId {
            persistence.saveEntries(entries, userId: uid)
        } else {
            persistence.save(entries)
        }
    }

    @MainActor
    func deleteAllEntries() {
        withAnimation(.easeInOut) {
            entries.removeAll()
        }
        if let uid = currentUserId {
            persistence.saveEntries(entries, userId: uid)
        } else {
            persistence.save(entries)
        }

        // Firestoreからも全削除
        if let userId = currentUserId {
            Task {
                try? await firestoreService.deleteAllEntries(for: userId)
            }
        }
    }

    private func publishSuccess(message: String) {
        withAnimation {
            lastSuccessMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            withAnimation {
                if self.lastSuccessMessage == message {
                    self.lastSuccessMessage = nil
                }
            }
        }
    }

    private func publishError(message: String) {
        withAnimation {
            lastErrorMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            withAnimation {
                if self.lastErrorMessage == message {
                    self.lastErrorMessage = nil
                }
            }
        }
    }

    // MARK: - 集計

    var recentEntries: [Entry] {
        Array(entries.prefix(7))
    }

    var trendSummary: String {
        let latest = Array(entries.prefix(14))
        guard !latest.isEmpty else {
            return "まだ記録がありません。今日の一言から始めてみましょう。"
        }

        let scores = latest.map { Double($0.mood.rawValue) }
        let average = scores.reduce(0, +) / Double(latest.count)
        let positives = latest.filter { $0.mood.rawValue > 0 }.count
        let negatives = latest.filter { $0.mood.rawValue < 0 }.count
        let tendency = average >= 0 ? "少し前向き" : "少しお疲れ気味"

        return
            "直近\(latest.count)件は\(tendency)。平均スコア \(String(format: "%.1f", average))、ポジ \(positives)／ネガ \(negatives)。"
    }

    var trendSnapshot: TrendSnapshot {
        let latest = Array(entries.prefix(14))
        guard !latest.isEmpty else { return .empty }
        let scores = latest.map { Double($0.mood.rawValue) }
        let average = scores.reduce(0, +) / Double(latest.count)
        let positives = latest.filter { $0.mood.rawValue > 0 }.count
        let negatives = latest.filter { $0.mood.rawValue < 0 }.count
        let tendency = average >= 0 ? "少し前向き" : "少しお疲れ気味"
        let dominantEmoji = latest.first?.mood.emoji ?? "🙂"
        let feedback =
            "\(latest.count)件は\(tendency)。平均 \(String(format: "%.1f", average))、ポジ \(positives)／ネガ \(negatives)。"
        let consecutiveDays =
            latest.first.map { entry in
                var count = 1
                var lastDate = Calendar.current.startOfDay(for: entry.date)
                for record in latest.dropFirst() {
                    let day = Calendar.current.startOfDay(for: record.date)
                    if Calendar.current.dateComponents([.day], from: day, to: lastDate).day == 1 {
                        count += 1
                        lastDate = day
                    } else {
                        break
                    }
                }
                return count
            } ?? 0

        return TrendSnapshot(
            averageScore: average,
            positiveRatio: Double(positives) / Double(latest.count),
            negativeRatio: Double(negatives) / Double(latest.count),
            consecutiveDays: consecutiveDays,
            sampleCount: latest.count,
            lastUpdated: latest.first?.date ?? Date(),
            dominantEmoji: dominantEmoji,
            feedback: feedback
        )
    }

    // MARK: - エクスポート

    @MainActor
    func exportEntriesJSON() -> String? {
        guard !entries.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries),
            let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }
}
