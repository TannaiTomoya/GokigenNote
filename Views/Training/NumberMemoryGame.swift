//
//  NumberMemoryGame.swift
//  GokigenNote
//

import SwiftUI

struct NumberMemoryGame: View {
    @ObservedObject var vm: TrainingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var numbers: [Int] = []
    @State private var phase: GamePhase = .ready
    @State private var userInput = ""
    @State private var attempts = 0
    @State private var correctAnswers = 0
    @State private var currentRoundCorrect = false
    @State private var showTimer = false
    @State private var timerProgress: Double = 1.0

    private let totalRounds = 10

    enum GamePhase {
        case ready
        case showing
        case hidden
        case result
        case finished
    }

    var body: some View {
        VStack(spacing: 24) {
            // スコア表示
            HStack {
                Label("\(correctAnswers)/\(attempts)", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Label("難易度 \(vm.difficulty)", systemImage: "speedometer")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // プログレスバー
            ProgressView(value: Double(attempts), total: Double(totalRounds))
                .tint(.blue)
                .padding(.horizontal)

            Spacer()

            // メインコンテンツ
            switch phase {
            case .ready:
                readyView
            case .showing:
                showingView
            case .hidden:
                hiddenView
            case .result:
                roundResultView
            case .finished:
                finishedView
            }

            Spacer()
        }
        .padding()
        .navigationTitle("数字記憶")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Views

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("準備はいいですか？")
                .font(.title2.weight(.semibold))

            Text("\(digitCount)桁の数字を覚えてください")
                .foregroundStyle(.secondary)

            Button("スタート") {
                startRound()
            }
            .buttonStyle(.borderedProminent)
            .font(.title3)
        }
    }

    private var showingView: some View {
        VStack(spacing: 16) {
            Text("覚えてください")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(numbers.map(String.init).joined())
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("数字: \(numbers.map(String.init).joined(separator: ", "))")

            // 表示時間のプログレス
            ProgressView(value: timerProgress)
                .tint(.orange)
                .padding(.horizontal, 40)
        }
    }

    private var hiddenView: some View {
        VStack(spacing: 20) {
            Text("覚えた数字を入力してください")
                .font(.headline)

            TextField("", text: $userInput)
                .font(.system(size: 40, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .accessibilityLabel("回答入力")

            Button("回答する") {
                checkAnswer()
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .disabled(userInput.isEmpty)
        }
    }

    private var roundResultView: some View {
        VStack(spacing: 16) {
            Image(systemName: currentRoundCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(currentRoundCorrect ? .green : .red)

            Text(currentRoundCorrect ? "正解！" : "おしい！")
                .font(.title2.weight(.bold))

            if !currentRoundCorrect {
                VStack(spacing: 4) {
                    Text("正解: \(numbers.map(String.init).joined())")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("あなたの回答: \(userInput)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if attempts < totalRounds {
                Button("次の問題へ") {
                    startRound()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var finishedView: some View {
        let finalScore = totalRounds > 0 ? Int(Double(correctAnswers) / Double(totalRounds) * 100) : 0

        return VStack(spacing: 20) {
            Image(systemName: finalScore >= 70 ? "star.circle.fill" : "hand.thumbsup.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(finalScore >= 70 ? .yellow : .blue)

            Text("トレーニング完了！")
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Text("スコア: \(finalScore)点")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.blue)

                Text("\(correctAnswers)/\(totalRounds) 正解")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(encouragementMessage(for: finalScore))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("完了") {
                vm.completeGame(
                    gameType: .numberMemory,
                    score: finalScore,
                    correctCount: correctAnswers,
                    totalCount: totalRounds
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
        }
    }

    // MARK: - Logic

    private var digitCount: Int {
        vm.difficulty + 2 // 難易度1 = 3桁, 難易度10 = 12桁
    }

    private func startRound() {
        let count = digitCount
        numbers = (0..<count).map { _ in Int.random(in: 0...9) }
        userInput = ""
        attempts += 1
        timerProgress = 1.0

        withAnimation {
            phase = .showing
        }

        // 表示時間: 桁数に応じて調整（最小1.5秒）
        let displayTime = max(1.5, Double(count) * 0.5)
        let steps = 20
        let interval = displayTime / Double(steps)

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                withAnimation(.linear) {
                    timerProgress = 1.0 - Double(i) / Double(steps)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + displayTime) {
            withAnimation {
                phase = .hidden
            }
        }
    }

    private func checkAnswer() {
        let correct = numbers.map(String.init).joined()
        currentRoundCorrect = (userInput == correct)

        if currentRoundCorrect {
            correctAnswers += 1
        }

        withAnimation {
            if attempts >= totalRounds {
                phase = .finished
            } else {
                phase = .result
            }
        }
    }

    private func encouragementMessage(for score: Int) -> String {
        switch score {
        case 90...100: return "素晴らしい！ワーキングメモリが鍛えられていますね。"
        case 70..<90:  return "いい調子です！続けることで確実に力がついています。"
        case 50..<70:  return "がんばりました！毎日少しずつ伸びていきますよ。"
        default:       return "挑戦できたこと自体が大事です。明日も一緒にやりましょう。"
        }
    }
}
