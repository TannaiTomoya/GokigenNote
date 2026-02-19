//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import SwiftUI
import FirebaseCore

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
                    MainTabView(authVM: authVM)
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
