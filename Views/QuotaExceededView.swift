//
//  QuotaExceededView.swift
//  GokigenNote
//
//  無料10回使い切ったときの専用シート。「そのLINE…」「今はやめる/続きを見る」で課金導線。
//

import SwiftUI

struct QuotaExceededView: View {
    private let coordinator = PaywallCoordinator.shared

    var body: some View {
        VStack(spacing: 24) {
            Text("本日の無料分を使い切りました")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("明日になるとまた使えます。\nプレミアムなら1日あたりの回数制限がありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    coordinator.dismissQuotaExceeded()
                }) {
                    Text("明日また使う")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    coordinator.dismissQuotaExceeded()
                    coordinator.present()
                }) {
                    Text("プレミアムを見る")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
    }
}

