//
//  GokigenViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import Foundation
import SwiftUI
import Combine

final class GokigenViewModel: ObservableObject {
    @Published var selectedMood: Mood = .neutral
    @Published var draftText: String = ""
    @Published var currentPrompt: String
    @Published private(set) var empathyDraft: String = ""
    @Published private(set) var nextStepDraft: String = ""
    @Published private(set) var reformulatedText: String = ""
    @Published private(set) var entries: [Entry] = []
    @Published var lastSuccessMessage: String?
    @Published var lastErrorMessage: String?
    @Published private(set) var isLoadingEmpathy: Bool = false
    @Published private(set) var isLoadingReformulation: Bool = false

    private enum Copy {
        static let saveSuccess = "あなたの今が書き留められたよ。"
        static let emptyDraft = "まず一言だけ書いてみませんか？"
        static let offlineFallback = "今は手元のアイデアで続けるね。"
        static let reformulationError = "言い換えに失敗しました。もう一度お試しください。"
    }

    private let persistence = Persistence.shared
    private let geminiService = GeminiService()
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
        // プロパティを明示的に初期化
        self.currentPrompt = PromptProvider.random()
        self.entries = persistence.load().sorted { $0.date > $1.date }
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

        // まずローカルの言い換えを即時反映
        let local = EmpathyEngine.rewrite(original: trimmed, mood: selectedMood)
        empathyDraft = local.0
        nextStepDraft = local.1

        if !forceRefresh,
           let cache = lastGeminiSuccess,
           cache.text == trimmed {
            empathyDraft = cache.response.empathy
            nextStepDraft = cache.response.nextStep
            return
        }

        if isLoadingEmpathy { return }

        isLoadingEmpathy = true
        lastGeminiRequest = trimmed

        Task {
            do {
                let response = try await geminiService.generateEmpathy(for: trimmed)
                await MainActor.run {
                    guard self.lastGeminiRequest == trimmed else { return }
                    self.empathyDraft = response.empathy
                    self.nextStepDraft = response.nextStep
                    self.lastGeminiSuccess = (text: trimmed, response: response)
                    self.lastGeminiRequest = nil
                    self.isLoadingEmpathy = false
                }
            } catch {
                await MainActor.run {
                    guard self.lastGeminiRequest == trimmed else { return }
                    self.publishError(message: Copy.offlineFallback)
                    self.lastGeminiRequest = nil
                    self.isLoadingEmpathy = false
                }
            }
        }
    }
    
    // 言語化機能
    @MainActor
    func reformulateText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        if isLoadingReformulation { return }

        isLoadingReformulation = true

        Task {
            do {
                let reformulated = try await geminiService.reformulateText(for: trimmed)
                await MainActor.run {
                    self.reformulatedText = reformulated
                    self.isLoadingReformulation = false
                }
            } catch {
                await MainActor.run {
                    self.publishError(message: Copy.reformulationError)
                    self.isLoadingReformulation = false
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

        let entry = Entry(
            date: Date(),
            mood: selectedMood,
            originalText: trimmed,
            reformulatedText: reformulatedText.isEmpty ? nil : reformulatedText,
            empathyText: empathy,
            nextStep: next
        )

        withAnimation(.easeInOut) {
            entries.insert(entry, at: 0)
        }
        persistence.save(entries)

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
        withAnimation(.easeInOut) {
            entries.remove(atOffsets: offsets)
        }
        persistence.save(entries)
    }

    @MainActor
    func move(from source: IndexSet, to destination: Int) {
        withAnimation(.easeInOut) {
            entries.move(fromOffsets: source, toOffset: destination)
        }
        persistence.save(entries)
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
