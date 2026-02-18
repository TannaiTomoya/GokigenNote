//
//  NBackGame.swift
//  GokigenNote
//

import SwiftUI

struct NBackGame: View {
    @ObservedObject var vm: TrainingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sequence: [Int] = []
    @State private var currentIndex = 0
    @State private var phase: GamePhase = .ready
    @State private var correctAnswers = 0
    @State private var totalJudgements = 0
    @State private var lastAnswer: AnswerResult?
    @State private var isShowingNumber = true

    private var nValue: Int { min(max(vm.difficulty, 1), 4) } // 1-back ～ 4-back
    private let sequenceLength = 20

    enum GamePhase {
        case ready
        case playing
        case finished
    }

    enum AnswerResult {
        case correct
        case incorrect
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label("\(correctAnswers)/\(totalJudgements)", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Label("\(nValue)-back", systemImage: "brain")
                    .font(.headline)
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal)

            if phase == .playing {
                ProgressView(value: Double(currentIndex), total: Double(sequenceLength))
                    .tint(.purple)
                    .padding(.horizontal)
            }

            Spacer()

            switch phase {
            case .ready:
                readyView
            case .playing:
                playingView
            case .finished:
                finishedView
            }

            Spacer()
        }
        .padding()
        .navigationTitle("n-backゲーム")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Views

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("\(nValue)-back チャレンジ")
                .font(.title2.weight(.semibold))

            VStack(spacing: 8) {
                Text("数字が次々と表示されます")
                Text("\(nValue)つ前と同じ数字なら「同じ！」を")
                Text("違うなら「違う！」を押してください")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            // 例の表示
            exampleView

            Button("スタート") {
                startGame()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .font(.title3)
        }
    }

    private var exampleView: some View {
        VStack(spacing: 4) {
            Text("例（\(nValue)-back）:")
                .font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(0..<min(nValue + 3, 6), id: \.self) { i in
                    let exampleNumbers = [3, 7, 5, 3, 7, 5]
                    VStack(spacing: 2) {
                        Text("\(exampleNumbers[i])")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .background(
                                i >= nValue && exampleNumbers[i] == exampleNumbers[i - nValue]
                                    ? Color.purple.opacity(0.2)
                                    : Color(.tertiarySystemBackground)
                            )
                            .cornerRadius(8)
                        if i >= nValue && exampleNumbers[i] == exampleNumbers[i - nValue] {
                            Text("同じ！")
                                .font(.system(size: 8))
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var playingView: some View {
        VStack(spacing: 30) {
            // 現在の数字
            Text(isShowingNumber && currentIndex < sequence.count ? "\(sequence[currentIndex])" : "")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 120, height: 120)
                .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))

            Text("\(currentIndex + 1) / \(sequenceLength)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // フィードバック
            if let answer = lastAnswer {
                HStack {
                    Image(systemName: answer == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(answer == .correct ? "正解！" : "ざんねん")
                }
                .font(.headline)
                .foregroundStyle(answer == .correct ? .green : .red)
                .transition(.scale.combined(with: .opacity))
            }

            // 判定ボタン（n個目以降のみ表示）
            if currentIndex >= nValue {
                HStack(spacing: 24) {
                    Button(action: { judge(isSame: true) }) {
                        VStack {
                            Image(systemName: "equal.circle.fill")
                                .font(.system(size: 44))
                            Text("同じ！")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Button(action: { judge(isSame: false) }) {
                        VStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                            Text("違う！")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                }
            } else {
                Text("数字を覚えてください（あと\(nValue - currentIndex)つ）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("次へ") {
                    advanceToNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
    }

    private var finishedView: some View {
        let finalScore = totalJudgements > 0 ? Int(Double(correctAnswers) / Double(totalJudgements) * 100) : 0

        return VStack(spacing: 20) {
            Image(systemName: finalScore >= 70 ? "star.circle.fill" : "hand.thumbsup.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(finalScore >= 70 ? .yellow : .purple)

            Text("トレーニング完了！")
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Text("スコア: \(finalScore)点")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.purple)

                Text("\(correctAnswers)/\(totalJudgements) 正解")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(nValue)-back レベル")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }

            Text(encouragementMessage(for: finalScore))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("完了") {
                vm.completeGame(
                    gameType: .nBack,
                    score: finalScore,
                    correctCount: correctAnswers,
                    totalCount: totalJudgements
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .font(.headline)
        }
    }

    // MARK: - Logic

    private func startGame() {
        // シーケンス生成: 約30%の確率でn個前と同じ数字になるよう調整
        sequence = []
        for i in 0..<sequenceLength {
            if i >= nValue && Double.random(in: 0...1) < 0.3 {
                sequence.append(sequence[i - nValue])
            } else {
                sequence.append(Int.random(in: 1...9))
            }
        }

        currentIndex = 0
        correctAnswers = 0
        totalJudgements = 0
        lastAnswer = nil

        withAnimation {
            phase = .playing
        }
    }

    private func judge(isSame: Bool) {
        guard currentIndex < sequence.count, currentIndex >= nValue else { return }

        let actuallyIsSame = sequence[currentIndex] == sequence[currentIndex - nValue]
        let isCorrect = (isSame == actuallyIsSame)

        totalJudgements += 1
        if isCorrect {
            correctAnswers += 1
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            lastAnswer = isCorrect ? .correct : .incorrect
        }

        // 少し待ってから次へ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            advanceToNext()
        }
    }

    private func advanceToNext() {
        lastAnswer = nil

        if currentIndex + 1 >= sequenceLength {
            withAnimation {
                phase = .finished
            }
        } else {
            // 数字を一瞬消してから次を表示
            withAnimation {
                isShowingNumber = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                currentIndex += 1
                withAnimation {
                    isShowingNumber = true
                }
            }
        }
    }

    private func encouragementMessage(for score: Int) -> String {
        switch score {
        case 90...100: return "驚異的！\(nValue)-backを完璧にこなしました。"
        case 70..<90:  return "いいペースです！ワーキングメモリが確実に強化されています。"
        case 50..<70:  return "n-backは難しいトレーニングです。よくがんばりました！"
        default:       return "n-backに挑戦した時点で成長しています。少しずつ慣れていきましょう。"
        }
    }
}
