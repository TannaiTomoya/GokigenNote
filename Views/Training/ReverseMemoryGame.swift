//
//  ReverseMemoryGame.swift
//  GokigenNote
//

import SwiftUI

struct ReverseMemoryGame: View {
    @ObservedObject var vm: TrainingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var numbers: [Int] = []
    @State private var phase: GamePhase = .ready
    @State private var userInput = ""
    @State private var attempts = 0
    @State private var correctAnswers = 0
    @State private var currentRoundCorrect = false
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
            HStack {
                Label("\(correctAnswers)/\(attempts)", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Label("難易度 \(vm.difficulty)", systemImage: "speedometer")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ProgressView(value: Double(attempts), total: Double(totalRounds))
                .tint(.green)
                .padding(.horizontal)

            Spacer()

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
        .navigationTitle("逆順記憶")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Views

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("逆順チャレンジ！")
                .font(.title2.weight(.semibold))

            Text("\(digitCount)桁の数字を逆順で答えてください")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("例: 1234 → 4321")
                .font(.headline)
                .foregroundStyle(.green)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            Button("スタート") {
                startRound()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .font(.title3)
        }
    }

    private var showingView: some View {
        VStack(spacing: 16) {
            Text("この数字を覚えてください")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(numbers.map(String.init).joined())
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                Text("逆順で答えてね")
            }
            .font(.caption)
            .foregroundStyle(.green)

            ProgressView(value: timerProgress)
                .tint(.green)
                .padding(.horizontal, 40)
        }
    }

    private var hiddenView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("逆順で入力してください")
                    .font(.headline)
                Text("さっきの数字を後ろから入力")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("", text: $userInput)
                .font(.system(size: 40, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Button("回答する") {
                checkAnswer()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
                    Text("元の数字: \(numbers.map(String.init).joined())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("正解（逆順）: \(numbers.reversed().map(String.init).joined())")
                        .font(.title3)
                        .foregroundStyle(.green)
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
                .tint(.green)
            }
        }
    }

    private var finishedView: some View {
        let finalScore = totalRounds > 0 ? Int(Double(correctAnswers) / Double(totalRounds) * 100) : 0

        return VStack(spacing: 20) {
            Image(systemName: finalScore >= 70 ? "star.circle.fill" : "hand.thumbsup.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(finalScore >= 70 ? .yellow : .green)

            Text("トレーニング完了！")
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Text("スコア: \(finalScore)点")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.green)

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
                    gameType: .reverseMemory,
                    score: finalScore,
                    correctCount: correctAnswers,
                    totalCount: totalRounds
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .font(.headline)
        }
    }

    // MARK: - Logic

    private var digitCount: Int {
        vm.difficulty + 2
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
        let correctReversed = numbers.reversed().map(String.init).joined()
        currentRoundCorrect = (userInput == correctReversed)

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
        case 90...100: return "素晴らしい！逆順思考が研ぎ澄まされていますね。"
        case 70..<90:  return "いい感じです！この調子で頭の柔軟性を高めましょう。"
        case 50..<70:  return "逆順は難しいですが、よくがんばりました！"
        default:       return "挑戦する姿勢が一番大事。明日はもっとスムーズになりますよ。"
        }
    }
}
