//
//  HistoryDetailView.swift
//  GokigenNote
//
//  履歴1件の詳細・フィードバック。
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HistoryDetailView: View {
    @ObservedObject var authVM: AuthViewModel
    let record: LineCheckRecord
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    RiskBadge(risk: record.risk)
                    Spacer()
                    Text(record.createdDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.oneLiner)
                    .font(.title3.weight(.bold))

                if let suggestions = record.suggestions, !suggestions.isEmpty {
                    Text("改善案")
                        .font(.headline)
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(s.text)
                                .font(.body)
                            Button("コピー") {
                                copyToPasteboard(s.text)
                                toast = "コピーしました"
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                Text("結果どうだった？")
                    .font(.headline)
                HStack {
                    feedbackButton("効いた", value: "worked")
                    feedbackButton("微妙", value: "didnt_work")
                    feedbackButton("送ってない", value: "not_sent")
                }
            }
            .padding()
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.toast = nil }
                    }
            }
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    private func feedbackButton(_ title: String, value: String) -> some View {
        Button(title) {
            Task {
                guard let uid = authVM.uid, let id = record.id else { return }
                try? await LineCheckRepository.shared.updateFeedback(uid: uid, checkId: id, feedback: value)
                toast = "保存しました"
            }
        }
        .buttonStyle(.bordered)
    }
}
