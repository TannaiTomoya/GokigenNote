//
//  QueueWaitOverlay.swift
//  GokigenNote
//
//  混雑時待機UI。年額の「優先処理」価値を体験させる。
//

import SwiftUI

struct QueueWaitOverlay: View {
    let elapsedSeconds: Int
    let plan: String
    let onUpgrade: () -> Void
    let onKeepWaiting: () -> Void
    let onRetryShorter: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                if shouldOfferPriority {
                    Button("優先で処理する（年額）") { onUpgrade() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                }

                HStack(spacing: 12) {
                    Button("このまま待つ") { onKeepWaiting() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("短くして再試行") { onRetryShorter() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .font(.subheadline)

                Text("経過: \(elapsedSeconds)秒")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 20)
        }
    }

    private var title: String {
        elapsedSeconds >= 5 ? "混雑しています" : "処理中…"
    }

    private var message: String {
        if elapsedSeconds < 5 {
            return "チェック結果を作成しています。"
        }
        if shouldOfferPriority {
            return "今はリクエストが集中しています。\n年額プランは優先処理で待ち時間が短くなります。"
        }
        return "今はリクエストが集中しています。\n順番に処理しています。"
    }

    private var shouldOfferPriority: Bool {
        if plan == "subscription_yearly" { return false }
        return elapsedSeconds >= 5
    }
}
