//
//  GokigenViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import Foundation
import SwiftUI
import Combine
@MainActor

final class GokigenViewModel: ObservableObject {
    @Published var selectedMood: Mood = .neutral
    @Published var draftText: String = ""
    @Published var currentPrompt: String = PromptProvider.random()
    @Published private(set) var empathyDraft: String = ""
    @Published private(set) var nextStepDraft: String = ""
    @Published private(set) var entries: [Entry] = []
    @Published var lastSuccessMessage: String?
    @Published var lastErrorMessage: String?

    private enum Copy {
        static let saveSuccess = "あなたの今が書き留められたよ。"
        static let emptyDraft = "まず一言だけ書いてみませんか？"
        static let offlineFallback = "今は手元のアイデアで続けるね。"
    }

    private let persistence = Persistence.shared
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

    init() {
        entries = persistence.load().sorted { $0.date > $1.date }
    }

    private var isDraftEmpty: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 入力補助

    func newPrompt() {
        currentPrompt = PromptProvider.random()
    }

    func insertMicExample() {
        guard isDraftEmpty, let sample = micExamples[selectedMood]?.randomElement() else { return }
        draftText = sample
    }

    // MARK: - ルールベース言い換え

    func buildEmpathyDraft() {
        guard !isDraftEmpty else { return }
        let (empathy, next) = EmpathyEngine.rewrite(original: draftText, mood: selectedMood)
        empathyDraft = empathy
        nextStepDraft = next
    }

    // MARK: - 保存 / 履歴

    func saveCurrentEntry() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publishError(message: Copy.emptyDraft)
            return
        }

        if empathyDraft.isEmpty {
            buildEmpathyDraft()
        }

        let entry = Entry(
            date: Date(),
            mood: selectedMood,
            originalText: trimmed,
            empathyText: empathyDraft,
            nextStep: nextStepDraft
        )

        withAnimation(.easeInOut) {
            entries.insert(entry, at: 0)
        }
        persistence.save(entries)

        draftText = ""
        selectedMood = .neutral
        empathyDraft = ""
        nextStepDraft = ""
        currentPrompt = PromptProvider.random()
        publishSuccess(message: Copy.saveSuccess)
    }

    func delete(at offsets: IndexSet) {
        withAnimation(.easeInOut) {
            entries.remove(atOffsets: offsets)
        }
        persistence.save(entries)
    }

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
            return "まだデータが少ないよ。1日の終わりに一言だけ書いてみよう。"
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
}

