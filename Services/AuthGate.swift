//
//  AuthGate.swift
//  GokigenNote
//
//  Auth 状態確定前に Firestore を触らないためのゲート（1箇所で守る）
//

import Foundation

enum AuthGateError: Error {
    case notReady
    case notSignedIn
}

struct AuthGate {
    /// authReady かつ ログイン済みのときのみ uid を返す。Firestore アクセス前に必ず呼ぶ。同期でOK（Published を読むだけ）。
    static func requireUID(authVM: AuthViewModel) throws -> String {
        guard authVM.authReady else { throw AuthGateError.notReady }
        guard let uid = authVM.uid else { throw AuthGateError.notSignedIn }
        return uid
    }
}
