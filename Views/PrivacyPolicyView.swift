//
//  PrivacyPolicyView.swift
//  GokigenNote
//
//  プライバシーポリシー（審査用）
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("プライバシーポリシー")
                        .font(.title2.bold())
                    Text("GokigenNoteは、ユーザーの個人情報を適切に取り扱います。")
                        .font(.body)

                    sectionTitle("取得する情報")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("・メールアドレス")
                        Text("・入力テキスト")
                        Text("・利用履歴")
                    }

                    sectionTitle("利用目的")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("・サービス提供")
                        Text("・機能改善")
                        Text("・サポート対応")
                    }

                    sectionTitle("第三者提供")
                    Text("法令に基づく場合を除き、第三者に提供しません。")

                    sectionTitle("外部サービス")
                    Text("本サービスはFirebaseを利用しています。")

                    sectionTitle("セキュリティ")
                    Text("適切な安全対策を講じます。")

                    sectionTitle("お問い合わせ")
                    Text("お問い合わせはアプリ内の設定画面からお願いします。")

                    Text("最終更新日：2026年1月")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("プライバシーポリシー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}
