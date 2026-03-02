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
            Text("そのLINE、このまま送ると危険です")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("あと1回だけ改善できます。\nそれ以降はプレミアムが必要です。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    coordinator.dismissQuotaExceeded()
                }) {
                    Text("今はやめる")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    coordinator.dismissQuotaExceeded()
                    coordinator.present()
                }) {
                    Text("続きを見る")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
    }
}

