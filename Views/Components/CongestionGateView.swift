//
//  CongestionGateView.swift
//  GokigenNote
//
//  混雑モーダル（resource-exhausted）。tier で standard/priority 出し分け。
//

import SwiftUI

struct CongestionGateView: View {
    let tier: QueueTier
    let retryAfterSeconds: Int?
    let onRetry: () -> Void
    let onUpgrade: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {

            Text("混雑中です")
                .font(.headline)

            if let sec = retryAfterSeconds {
                Text("あと\(sec)秒で再試行できます")
                    .foregroundStyle(.secondary)
            }

            if tier == .standard {
                Button("優先でチェック（年額）") {
                    onUpgrade()
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button("再試行") { onRetry() }
                        .buttonStyle(.bordered)
                    Button("このまま待つ") { onClose() }
                        .buttonStyle(.bordered)
                }

                Text("あとでいつでも変更できます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            } else {
                Button("再試行") { onRetry() }
                    .buttonStyle(.borderedProminent)
                Button("閉じる") { onClose() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

#Preview {
    CongestionGateView(
        tier: .standard,
        retryAfterSeconds: nil,
        onRetry: {},
        onUpgrade: {},
        onClose: {}
    )
}
