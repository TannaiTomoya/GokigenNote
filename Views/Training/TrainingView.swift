//
//  TrainingView.swift
//  GokigenNote
//

import SwiftUI

struct TrainingView: View {
    @ObservedObject var vm: TrainingViewModel
    @ObservedObject var gokigenVM: GokigenViewModel
    @State private var selectedGame: GameType?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    streakCard
                    todayStatusCard
                    gameCards
                    progressSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("トレーニング")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedGame) { game in
                NavigationStack {
                    gameView(for: game)
                }
            }
            .sheet(isPresented: $vm.showPostTrainingMood) {
                PostTrainingMoodView(trainingVM: vm, gokigenVM: gokigenVM)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日のトレーニング")
                .font(.largeTitle.weight(.bold))
            Text("毎日続けることで、ワーキングメモリが強化されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(vm.streak)日連続")
                    .font(.title2.weight(.bold))
                Text(streakMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.streak)日連続トレーニング中")
    }

    private var todayStatusCard: some View {
        HStack(spacing: 20) {
            statItem(title: "今日", value: "\(vm.todaySessionCount)回", icon: "calendar.badge.checkmark", color: .blue)
            statItem(title: "ベスト", value: "\(vm.bestScore)点", icon: "trophy.fill", color: .yellow)
            statItem(title: "平均", value: String(format: "%.0f点", vm.averageScore), icon: "chart.bar.fill", color: .green)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var gameCards: some View {
        VStack(spacing: 12) {
            Text("ゲームを選ぶ")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            GameCard(
                title: GameType.numberMemory.title,
                description: GameType.numberMemory.description,
                icon: GameType.numberMemory.icon,
                color: .blue
            ) {
                selectedGame = .numberMemory
            }

            GameCard(
                title: GameType.reverseMemory.title,
                description: GameType.reverseMemory.description,
                icon: GameType.reverseMemory.icon,
                color: .green
            ) {
                selectedGame = .reverseMemory
            }

            GameCard(
                title: GameType.nBack.title,
                description: GameType.nBack.description,
                icon: GameType.nBack.icon,
                color: .purple
            ) {
                selectedGame = .nBack
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近の成績")
                .font(.headline)

            if vm.recentSessions().isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("まだ記録がありません")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.recentSessions()) { session in
                    HStack {
                        Image(systemName: session.gameType.icon)
                            .foregroundStyle(colorForGameType(session.gameType))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.gameType.title)
                                .font(.subheadline.weight(.medium))
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(session.score)点")
                            .font(.headline)
                            .foregroundStyle(colorForScore(session.score))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func gameView(for game: GameType) -> some View {
        switch game {
        case .numberMemory:
            NumberMemoryGame(vm: vm)
        case .reverseMemory:
            ReverseMemoryGame(vm: vm)
        case .nBack:
            NBackGame(vm: vm)
        }
    }

    private var streakMessage: String {
        switch vm.streak {
        case 0:      return "今日から始めよう！"
        case 1:      return "いいスタート！明日も続けよう"
        case 2...6:  return "いい調子！このペースで続けよう"
        case 7...13: return "1週間以上！習慣になってきたね"
        case 14...29: return "2週間以上！確実に力がついています"
        default:     return "すごい！\(vm.streak)日も続けています！"
        }
    }

    private func colorForGameType(_ type: GameType) -> Color {
        switch type {
        case .numberMemory:  return .blue
        case .reverseMemory: return .green
        case .nBack:         return .purple
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .blue
        case 40..<60:  return .orange
        default:       return .secondary
        }
    }
}

// MARK: - GameCard

struct GameCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(color)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(description)")
        .accessibilityHint("タップしてゲームを開始")
    }
}
