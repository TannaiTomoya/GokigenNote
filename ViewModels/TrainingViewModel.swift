//
//  TrainingViewModel.swift
//  GokigenNote
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TrainingViewModel: ObservableObject {
    // MARK: - Published State

    @Published var difficulty: Int = 1          // 1-10
    @Published private(set) var history: [TrainingSession] = []
    @Published private(set) var streak: Int = 0
    @Published var showPostTrainingMood = false
    @Published var lastCompletedSession: TrainingSession?

    private let persistence = TrainingPersistence.shared
    private let firestoreService = FirestoreService.shared
    private var currentUserId: String?

    // MARK: - Init

    init() {
        loadHistory()
        calculateStreak()
    }

    func setUserId(_ userId: String?) {
        guard currentUserId != userId else { return }
        currentUserId = userId
    }

    // MARK: - Game Completion

    func completeGame(gameType: GameType, score: Int, correctCount: Int, totalCount: Int) {
        let session = TrainingSession(
            date: Date(),
            gameType: gameType,
            difficulty: difficulty,
            score: score,
            correctCount: correctCount,
            totalCount: totalCount
        )

        history.insert(session, at: 0)
        persistence.save(history)
        lastCompletedSession = session
        showPostTrainingMood = true
        calculateStreak()

        // Firestoreにも保存
        if let userId = currentUserId {
            Task {
                try? await saveToFirestore(session, for: userId)
            }
        }

        // 自動で難易度を調整
        adjustDifficulty(basedOn: score)
    }

    // MARK: - Difficulty

    private func adjustDifficulty(basedOn score: Int) {
        if score >= 80 && difficulty < 10 {
            difficulty += 1
        } else if score < 40 && difficulty > 1 {
            difficulty -= 1
        }
    }

    // MARK: - Streak Calculation

    private func calculateStreak() {
        guard !history.isEmpty else {
            streak = 0
            return
        }

        let calendar = Calendar.current
        var count = 0
        let today = calendar.startOfDay(for: Date())

        // 今日か昨日に記録があるか確認
        let latestDay = calendar.startOfDay(for: history[0].date)
        let daysSinceLatest = calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0
        guard daysSinceLatest <= 1 else {
            streak = 0
            return
        }

        // ユニークな日を収集
        var uniqueDays: Set<Date> = []
        for session in history {
            uniqueDays.insert(calendar.startOfDay(for: session.date))
        }

        let sortedDays = uniqueDays.sorted(by: >)
        var lastDate = sortedDays[0]
        count = 1

        for day in sortedDays.dropFirst() {
            if calendar.dateComponents([.day], from: day, to: lastDate).day == 1 {
                count += 1
                lastDate = day
            } else {
                break
            }
        }

        streak = count
    }

    // MARK: - Statistics

    var todaySessionCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return history.filter { Calendar.current.startOfDay(for: $0.date) == today }.count
    }

    var bestScore: Int {
        history.map(\.score).max() ?? 0
    }

    var averageScore: Double {
        guard !history.isEmpty else { return 0 }
        return Double(history.map(\.score).reduce(0, +)) / Double(history.count)
    }

    func recentSessions(limit: Int = 5) -> [TrainingSession] {
        Array(history.prefix(limit))
    }

    func sessions(for gameType: GameType) -> [TrainingSession] {
        history.filter { $0.gameType == gameType }
    }

    // MARK: - Persistence

    private func loadHistory() {
        history = persistence.load().sorted { $0.date > $1.date }
    }

    private func saveToFirestore(_ session: TrainingSession, for userId: String) async throws {
        // Firestoreに保存するためのデータ構造
        // FirestoreServiceに将来的にtraining用メソッドを追加可能
        // 現時点ではローカル保存のみで十分
    }
}

// MARK: - Notification for Mental Care Integration

extension Notification.Name {
    static let trainingCompleted = Notification.Name("trainingCompleted")
}
