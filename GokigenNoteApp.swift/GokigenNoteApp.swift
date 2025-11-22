//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//    FirebaseApp.configure()
      FirebaseManager.shared.configure()
    return true
  }
}


@main
struct GokigenNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authVM = AuthViewModel()
    
    init() {
        // Firebase初期化
        //FirebaseManager.shared.configure()
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
            .onAppear {
                print("🏁 [GokigenNoteApp] アプリ起動")
                print("🏁 [GokigenNoteApp] isAuthenticated: \(authVM.isAuthenticated)")
            }
        }
    }
}
