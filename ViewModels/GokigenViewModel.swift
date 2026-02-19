//
//  GokigenViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

final class GokigenViewModel: ObservableObject {
    @Published var selectedMood: Mood = .neutral
    @Published var draftText: String = ""
    @Published var reformulationPurpose: ReformulationPurpose = .shareFeeling
    @Published var reformulationAudience: ReformulationAudience = .colleague
    @Published var reformulationTone: ReformulationTone = .soft
    @Published var currentPrompt: String
    @Published private(set) var empathyDraft: String = ""
    @Published private(set) var nextStepDraft: String = ""
    @Published private(set) var reformulatedText: String = ""
    @Published private(set) var entries: [Entry] = []
    @Published var lastSuccessMessage: String?
    @Published var lastErrorMessage: String?
    @Published private(set) var isLoadingEmpathy: Bool = false
    @Published private(set) var isLoadingReformulation: Bool = false
    @Published private(set) var isLoadingEntries: Bool = false
    @Published private(set) var canLoadMore: Bool = true
    @Published private(set) var isSyncing: Bool = false

    private enum Copy {
        static let saveSuccess = "あなたの今が書き留められたよ。"
        static let emptyDraft = "まず一言だけ書いてみませんか？"
        static let offlineFallback = "今は手元のアイデアで続けるね。"
        static let reformulationError = "言い換えに失敗しました。もう一度お試しください。"
        static let dailyLimitReached = "本日の利用回数に達したため、簡易表示しています。"
        static let fallbackReformulation = "通信のため簡易表示しています。"
    }

    /// 1日あたりの Gemini API 呼び出し上限（Phase 2）
    private static let dailyAPICallLimit = 30
    /// 言い換えキャッシュの最大件数（Phase 1）
    private static let reformulationCacheMaxCount = 50

    private var reformulationCache: [String: String] = [:]
    private var reformulationCacheOrder: [String] = []

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
        switch token.kind {
        case .empathy:
            guard empathyRequestID == token.id else { return }
            empathyRequestID = nil
            isLoadingEmpathy = false
        case .reformulation:
            guard reformulationRequestID == token.id else { return }
            reformulationRequestID = nil
            isLoadingReformulation = false
        }
        aiLock = false
    }

    /// ここでは “消費しない”。不足なら Paywall（Coordinator が throttle を担当）
    @MainActor
    private func ensureQuotaOrOpenPaywall() -> Bool {
        let pm = PremiumManager.shared
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

    /// 目的・相手・トーンを含むキャッシュキー（同じ入力でもコンテキストで別結果）
    private func reformulationCacheKey(trimmed: String) -> String {
        "\(trimmed)|\(reformulationPurpose.rawValue)|\(reformulationAudience.rawValue)|\(reformulationTone.rawValue)"
    }

    /// 言い換え結果をキャッシュに追加（最大件数で古いものを削除）（Phase 1）
    private func setReformulationCache(cacheKey: String, result: String) {
        if reformulationCacheOrder.count >= Self.reformulationCacheMaxCount, let first = reformulationCacheOrder.first {
            reformulationCacheOrder.removeFirst()
            reformulationCache.removeValue(forKey: first)
        }
        if !reformulationCacheOrder.contains(cacheKey) {
            reformulationCacheOrder.append(cacheKey)
        }
        reformulationCache[cacheKey] = result
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
            "頑張ったぶん褒めてもらえて、心がふわっと温かくなった。"
        ],
        .happy: [
            "ちょっとした会話が楽しくて気持ちが軽くなった。",
            "好きな音楽を聴いたら自然と前向きになれた。"
        ],
        .neutral: [
            "特別な出来事はなかったけれど穏やかだった。",
            "いつものペースで進められて少し安心した。"
        ],
        .sad: [
            "思っていたより疲れが残っていて少し落ち込んだ。",
            "自分の気持ちをうまく伝えられず、もどかしい。"
        ],
        .verySad: [
            "ずっと心がざわついていて、深呼吸を忘れていたかも。",
            "エネルギーが出ず、誰かに頼りたい気持ちが強かった。"
        ]
    ]

    @MainActor
    init() {
        self.currentPrompt = PromptProvider.random()
        self.entries = []
    }

    func setUserId(_ userId: String) {
        guard currentUserId != userId else { return }
        currentUserId = userId

        // ① ローカル先出し（即表示）
        let cached = persistence.loadEntries(userId: userId)
        self.entries = cached.sorted { $0.date > $1.date }

        // ② pending 再送（先に実行）
        flushPending()

        // ③ 裏で Firestore 初回ページ同期
        loadInitial(userId: userId)
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
            defer { Task { @MainActor in self.isFlushingPending = false } }

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
        return dict.values.sorted { $0.date > $1.date }
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
                    self.canLoadMore = !result.entries.isEmpty && result.entries.count == 30 && result.lastDoc != nil
                    self.isSyncing = false
                    self.persistence.saveEntries(self.entries, userId: userId)
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
                    if lastEntryDoc == nil {
                        self.entries = result.entries.sorted { $0.date > $1.date }
                    } else {
                        self.entries = (self.entries + result.entries).sorted { $0.date > $1.date }
                    }
                    self.lastEntryDoc = result.lastDoc
                    self.canLoadMore = !result.entries.isEmpty && result.entries.count == 30 && result.lastDoc != nil
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
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
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
           cache.text == trimmed {
            empathyDraft = cache.response.empathy
            nextStepDraft = cache.response.nextStep
            return
        }

        // 日次上限は0消費で終了
        guard canCallGeminiAPI() else {
            publishError(message: Copy.dailyLimitReached)
            return
        }

        // 課金枠が無ければPaywall（まだ消費しない）
        guard ensureQuotaOrOpenPaywall() else { return }

        // リクエスト開始（解除漏れをdeferで潰す）
        guard let token = beginAIRequest(kind: .empathy) else { return }

        // ここで初めて消費＆APIカウント
        consumeQuota()
        recordGeminiAPICall()

        lastGeminiRequest = trimmed

        Task {
            defer { Task { @MainActor in self.endAIRequest(token) } }

            do {
                let response = try await geminiService.generateEmpathy(for: trimmed)
                await MainActor.run {
                    guard self.empathyRequestID == token.id else { return }
                    guard self.lastGeminiRequest == trimmed else { return }

                    self.empathyDraft = response.empathy
                    self.nextStepDraft = response.nextStep
                    self.lastGeminiSuccess = (text: trimmed, response: response)
                    self.lastGeminiRequest = nil
                }
            } catch {
                await MainActor.run {
                    guard self.empathyRequestID == token.id else { return }
                    guard self.lastGeminiRequest == trimmed else { return }

                    self.publishError(message: Copy.offlineFallback)
                    self.lastGeminiRequest = nil
                }
            }
        }
    }
    
    @MainActor
    func reformulateText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        let context = ReformulationContext(
            purpose: reformulationPurpose,
            audience: reformulationAudience,
            tone: reformulationTone
        )
        let cacheKey = reformulationCacheKey(trimmed: trimmed)

        // キャッシュヒットは0消費
        if let cached = reformulationCache[cacheKey] {
            reformulatedText = cached
            return
        }

        // 日次上限は0消費でローカル簡易
        guard canCallGeminiAPI() else {
            reformulatedText = EmpathyEngine.reformulateLocal(original: trimmed)
            publishError(message: Copy.dailyLimitReached)
            return
        }

        // 課金枠が無ければPaywall（まだ消費しない）
        guard ensureQuotaOrOpenPaywall() else { return }

        // リクエスト開始
        guard let token = beginAIRequest(kind: .reformulation) else { return }

        // ここで初めて消費＆APIカウント
        consumeQuota()
        recordGeminiAPICall()

        Task {
            defer { Task { @MainActor in self.endAIRequest(token) } }

            do {
                let reformulated = try await geminiService.reformulateText(for: trimmed, context: context)
                await MainActor.run {
                    guard self.reformulationRequestID == token.id else { return }

                    self.reformulatedText = reformulated
                    self.setReformulationCache(cacheKey: cacheKey, result: reformulated)
                }
            } catch {
                await MainActor.run {
                    guard self.reformulationRequestID == token.id else { return }

                    self.reformulatedText = EmpathyEngine.reformulateLocal(original: trimmed)
                    self.publishError(message: Copy.fallbackReformulation)
                }
            }
        }
    }

    // MARK: - 保存 / 履歴

    @MainActor
    func saveCurrentEntry() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        var empathy = empathyDraft
        var next = nextStepDraft
        if empathy.isEmpty || next.isEmpty {
            let fallback = EmpathyEngine.rewrite(original: trimmed, mood: selectedMood)
            empathy = fallback.0
            next = fallback.1
        }

        var entry = Entry(
            date: Date(),
            mood: selectedMood,
            originalText: trimmed,
            reformulatedText: reformulatedText.isEmpty ? nil : reformulatedText,
            empathyText: empathy,
            nextStep: next
        )
        entry.updatedAt = Date()

        print("💾 [GokigenViewModel] エントリを保存: originalText=\(trimmed.prefix(30))..., reformulatedText=\(reformulatedText.isEmpty ? "なし" : reformulatedText.prefix(30).description + "...")")

        withAnimation(.easeInOut) {
            entries.insert(entry, at: 0)
        }
        if let uid = currentUserId {
            persistence.saveEntries(entries, userId: uid)
        } else {
            persistence.save(entries)
        }

        // Firestoreにも保存（失敗時は pending に積む。成功時は pending から消す）
        if let userId = currentUserId {
            Task {
                do {
                    try await firestoreService.saveEntry(entry, for: userId)
                    dequeuePending(entry.id, userId: userId)
                    print("✅ [GokigenViewModel] Firestoreへの保存成功")
                } catch {
                    enqueuePending(entry.id, userId: userId)
                    print("❌ [GokigenViewModel] Firestoreへの保存失敗（pending に追加）: \(error.localizedDescription)")
                }
            }
        } else {
            print("⚠️ [GokigenViewModel] ユーザーIDなし、ローカルのみ保存")
        }

        draftText = ""
        selectedMood = .neutral
        empathyDraft = ""
        nextStepDraft = ""
        reformulatedText = ""
        currentPrompt = PromptProvider.random()
        publishSuccess(message: Copy.saveSuccess)
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
                    try? await firestoreService.deleteEntry(entry.id, for: userId)
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

        return "直近\(latest.count)件は\(tendency)。平均スコア \(String(format: "%.1f", average))、ポジ \(positives)／ネガ \(negatives)。"
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
        let feedback = "\(latest.count)件は\(tendency)。平均 \(String(format: "%.1f", average))、ポジ \(positives)／ネガ \(negatives)。"
        let consecutiveDays = latest.first.map { entry in
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
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
