//
//  PaywallView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2026/02/27.
//
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("プレミアム")
                    .font(.title).bold()

                Text("制限を解除して、送信前チェックをもっと使えるようにします。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let msg = PremiumManager.shared.lastErrorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("購入を復元") {
                    Task { await PremiumManager.shared.restorePurchases() }
                }
                .buttonStyle(.borderedProminent)

                Button("閉じる") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
