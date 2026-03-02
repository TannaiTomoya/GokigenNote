//
//  HighRiskGateView.swift
//  GokigenNote
//
//  HIGH判定＝送信前ロック。出し分けは queueTier のみで行う（plan 文字列のズレを排除）。
//

import SwiftUI

struct HighRiskGateView: View {
    @Environment(\.dismiss) private var dismiss

    /// Functions 返却の "priority" | "standard"
    let queueTier: String
    let onContinueStandard: () -> Void
    let onUpgradeYearly: () -> Void

    private var isPriority: Bool { queueTier == "priority" }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ 送ると後悔する可能性が高いです")
                        .font(.title3).bold()
                    Text("このまま送ると、相手を追い詰める言い回しになっているかもしれません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPriority {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("優先処理でチェック中")
                            .font(.headline)
                        Text("混雑時でも待ち時間を短縮しています。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onContinueStandard()
                        dismiss()
                    } label: {
                        Text("改善案を見て送信前に整える")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("混雑時は少し待つことがあります")
                            .font(.headline)
                        Text("年額プランなら、送信前チェックを優先処理します。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onUpgradeYearly()
                        dismiss()
                    } label: {
                        Text("年額で混雑時も優先")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onContinueStandard()
                        dismiss()
                    } label: {
                        Text("今は通常で続ける")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("送信前チェック")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        onContinueStandard()
                        dismiss()
                    }
                }
            }
        }
    }
}
