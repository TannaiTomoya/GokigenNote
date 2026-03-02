//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  ルート: signedOut のとき AuthView、それ以外は MainTabView。
//  OAuth リダイレクトは .onOpenURL で Firebase Auth に渡す。
//

import SwiftUI
import FirebaseAuth

@main
struct GokigenNoteApp: App {
    @StateObject private var authVM = AuthViewModel()
    @ObservedObject private var congestionPresenter = CongestionGatePresenter.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.authState == .signedOut {
                    AuthView(authVM: authVM)
                } else {
                    MainTabView(authVM: authVM)
                }
            }
            .onOpenURL { url in
                _ = Auth.auth().canHandle(url)
            }
            .task {
                for await req in await RetryBus.shared.stream() {
                    let action: CongestionRetryAction = switch req.op {
                    case .lineStopper: .lineStopper
                    case .reformulate: .reformulate
                    case .empathy: .empathy
                    }
                    await MainActor.run {
                        RetryBus.post(action)
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { congestionPresenter.isPresented },
                set: { if !$0 { congestionPresenter.dismiss() } }
            )) {
                let presenter = CongestionGatePresenter.shared
                if let details = presenter.details,
                   let retry = presenter.retryRequest {

                    CongestionGateView(
                        tier: details.queueTier,
                        retryAfterSeconds: details.retryAfterSeconds,
                        onRetry: {
                            presenter.dismiss()
                            Task { await RetryBus.shared.send(retry) }
                        },
                        onUpgrade: {
                            presenter.dismiss()
                            PaywallCoordinator.shared.present(preselect: .yearly)
                        },
                        onClose: { presenter.dismiss() }
                    )
                    .presentationDetents([.height(280)])
                } else {
                    Text("混雑しています。しばらくしてからお試しください。")
                        .padding()
                }
            }
        }
    }
}
