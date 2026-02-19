//
//  FirebaseManager.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import FirebaseCore
import FirebaseAuth

final class FirebaseManager {
    static let shared = FirebaseManager()
    
    private init() {}

    /// Firebase 初期化は GokigenNoteApp.init() で FirebaseApp.configure() を1回だけ呼ぶ方針。二重実行防止用。
    func configure() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
    
    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }
    
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    var currentUserId: String? {
        currentUser?.uid
    }
}

