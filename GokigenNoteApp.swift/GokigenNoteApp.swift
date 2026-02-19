//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import SwiftUI
import FirebaseCore

/// 一時的: ログイン後のクラッシュ原因を MainTabView 配下に絞るための仮 View
private struct PostLoginDebugView: View {
    var body: some View {
        Text("Logged in OK")
    }
}

@main
struct GokigenNoteApp: App {
    @StateObject private var authVM = AuthViewModel()
    @ObservedObject private var paywall = PaywallCoordinator.shared

    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isAuthenticated {
                    // 一時的: MainTabView の代わりに仮 View でクラッシュ箇所を切り分け
                    PostLoginDebugView()
                    // MainTabView(authVM: authVM)
                } else {
                    AuthView(authVM: authVM)
                }
            }
            .task {
                PremiumManager.shared.start()
            }
            .sheet(isPresented: Binding(
                get: { paywall.isPresented },
                set: { newValue in
                    if !newValue { paywall.dismiss() }
                }
            )) {
                PaywallView()
            }
            .onAppear {
                print("🏁 [GokigenNoteApp] アプリ起動")
                print("🏁 [GokigenNoteApp] isAuthenticated: \(authVM.isAuthenticated)")
            }
        }
    }
}
