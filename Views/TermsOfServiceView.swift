//
//  TermsOfServiceView.swift
//  GokigenNote
//
//  利用規約（審査用）
//

import Combine
import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("利用規約（Terms of Service）")
                        .font(.title2.bold())
                    Text("本利用規約（以下「本規約」）は、GokigenNote（以下「本サービス」）の利用条件を定めるものです。")
                        .font(.body)

                    sectionTitle("第1条（適用）")
                    Text("本規約は、ユーザーと運営者との間の本サービスの利用に関わる一切の関係に適用されます。")

                    sectionTitle("第2条（利用登録）")
                    Text("ユーザーは、本サービスを利用することで本規約に同意したものとみなします。")

                    sectionTitle("第3条（サービス内容）")
                    Text("本サービスは、ユーザーの入力内容をもとに、文章の言い換えや思考整理の支援を行うものです。")

                    sectionTitle("第4条（課金・サブスクリプション）")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("・一部機能は有料プランで提供されます")
                        Text("・サブスクリプションは自動更新されます")
                        Text("・更新日の24時間前までに解約しない限り自動更新されます")
                        Text("・解約はApple IDの設定画面から行えます")
                        Text("・購入済み期間の途中解約による返金は行われません")
                    }

                    sectionTitle("第5条（禁止事項）")
                    Text("以下の行為を禁止します：不正アクセス、サービスの妨害、不正利用")

                    sectionTitle("第6条（免責事項）")
                    Text("本サービスの利用により発生したいかなる損害についても、運営者は責任を負いません。")

                    sectionTitle("第7条（サービス変更・終了）")
                    Text("本サービスは予告なく変更または終了する場合があります。")

                    sectionTitle("第8条（規約変更）")
                    Text("本規約は必要に応じて変更される場合があります。")

                    sectionTitle("第9条（準拠法）")
                    Text("本規約は日本法に準拠します。")

                    Text("最終更新日：2026年1月")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("利用規約")
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
