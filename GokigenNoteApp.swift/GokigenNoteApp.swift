//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import SwiftUI
import FirebaseCore

#if canImport(UIKit)
import UIKit
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}

@main
struct GokigenNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authVM = AuthViewModel()
    @ObservedObject private var paywall = PaywallCoordinator.shared

    init() {
        PremiumManager.shared.start()
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
        .onChange(of: scenePhase) { newValue in
            if newValue == .active {
                Task { await PremiumManager.shared.refreshEntitlements(mode: .startupCautious) }
            }
        }
    }
}
