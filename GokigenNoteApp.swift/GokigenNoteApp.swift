//
//  GokigenNoteApp.swift
//  GokigenNote
//
//  ルート: signedOut のとき AuthView、それ以外は MainTabView。
//

import SwiftUI

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
        }
    }
}
