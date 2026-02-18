//
//  PostTrainingMoodView.swift
//  GokigenNote
//

import SwiftUI

/// トレーニング後に気分を記録するシート
struct PostTrainingMoodView: View {
    @ObservedObject var trainingVM: TrainingViewModel
    @ObservedObject var gokigenVM: GokigenViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMood: Mood = .neutral
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 結果サマリー
                    if let session = trainingVM.lastCompletedSession {
                        resultSummary(session)
                    }

                    // 気分選択
                    moodSection

                    // メモ入力
                    noteSection

                    // 保存ボタン
                    saveButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("トレーニング後の気分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("スキップ") { dismiss() }
                }
            }
        }
    }

    private func resultSummary(_ session: TrainingSession) -> some View {
        VStack(spacing: 12) {
            Image(systemName: session.score >= 70 ? "star.circle.fill" : "hand.thumbsup.fill")
                .font(.system(size: 44))
                .foregroundStyle(session.score >= 70 ? .yellow : .blue)

            Text("\(session.gameType.title) — \(session.score)点")
                .font(.title3.weight(.semibold))

            Text(encouragement(for: session.score))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今の気分は？")
                .font(.headline)

            Picker("気分", selection: $selectedMood) {
                ForEach(Mood.allCases) { mood in
                    Text(mood.emoji)
                        .accessibilityLabel(mood.label)
                        .tag(mood)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一言メモ（任意）")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("トレーニングしてみてどうだった？")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 6)
                }
                TextEditor(text: $note)
                    .frame(minHeight: 80)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var saveButton: some View {
        Button(action: saveEntry) {
            Text("気分を記録する")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func saveEntry() {
        guard let session = trainingVM.lastCompletedSession else {
            dismiss()
            return
        }

        let text: String
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "トレーニング完了！ \(session.gameType.title) \(session.score)点"
        } else {
            text = "\(note)\n（\(session.gameType.title) \(session.score)点）"
        }

        // GokigenViewModelに一時的にデータを設定して保存
        gokigenVM.selectedMood = selectedMood
        gokigenVM.draftText = text
        gokigenVM.saveCurrentEntry()

        dismiss()
    }

    private func encouragement(for score: Int) -> String {
        switch score {
        case 80...100: return "できた！この体験を大切にしてね。"
        case 60..<80:  return "よくがんばりました！成長を感じてね。"
        default:       return "挑戦できた自分を褒めてあげよう。"
        }
    }
}
