//
//  LineStopperWaitingGate.swift
//  GokigenNote
//
//  5秒以上ローディングかつ standard のとき CongestionGateView を sheet で表示。
//

import SwiftUI

struct LineStopperWaitingGate: View {
    let queueTier: String
    @Binding var isLoading: Bool
    @State private var showGate = false
    /// 「このまま待つ」押下後はゲートを閉じて待機継続（B案）。下部に補足を表示。
    @State private var userChoseWait = false

    private var tier: QueueTier {
        queueTier == "priority" ? .priority : .standard
    }

    var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("チェック中…")
                        .font(.headline)
                    Text("送る前に一呼吸。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if userChoseWait {
                        Text("順番に処理しています。\n混雑が解消次第、結果を表示します。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: Binding(
            get: { showGate && tier == .standard && isLoading },
            set: { if !$0 { showGate = false } }
        )) {
            CongestionGateView(
                tier: .standard,
                retryAfterSeconds: nil,
                onRetry: {
                    userChoseWait = true
                    showGate = false
                },
                onUpgrade: {
                    showGate = false
                    PaywallCoordinator.shared.present(preselect: .yearly)
                },
                onClose: { showGate = false }
            )
        }
        .task(id: isLoading) {
            guard isLoading else { showGate = false; userChoseWait = false; return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if isLoading { withAnimation { showGate = true } }
        }
    }
}
