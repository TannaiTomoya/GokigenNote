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
        }
    }
}
