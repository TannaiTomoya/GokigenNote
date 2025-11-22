//
//  AuthService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import FirebaseAuth
import FirebaseCore

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case userNotFound
    case wrongPassword
    case emailAlreadyInUse
    case networkError
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "メールアドレスの形式が正しくありません"
        case .weakPassword:
            return "パスワードは6文字以上で入力してください"
        case .userNotFound:
            return "ユーザーが見つかりません"
        case .wrongPassword:
            return "パスワードが正しくありません"
        case .emailAlreadyInUse:
            return "このメールアドレスは既に使用されています"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .unknown(let message):
            return message
        }
    }
}

final class AuthService {
    static let shared = AuthService()
    private init() {}
    
    // MARK: - Email & Password Authentication
    
    func signUp(email: String, password: String) async throws -> FirebaseAuth.User {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            return result.user
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }
    
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return result.user
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }
    
    // MARK: - Google Sign In (OAuth Provider)
    
    @MainActor
    func signInWithGoogle() async throws -> FirebaseAuth.User {
        let provider = OAuthProvider(providerID: "google.com")
        
        // スコープの設定（オプション）
        provider.scopes = ["email", "profile"]
        
        // カスタムパラメータ（オプション）
        provider.customParameters = [
            "prompt": "select_account"
        ]
        
        do {
            // iOS 13+ で利用可能なメソッド
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
                provider.getCredentialWith(nil) { credential, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let credential = credential else {
                        continuation.resume(throwing: AuthError.unknown("認証情報の取得に失敗しました"))
                        return
                    }
                    
                    Auth.auth().signIn(with: credential) { authResult, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let authResult = authResult {
                            continuation.resume(returning: authResult)
                        } else {
                            continuation.resume(throwing: AuthError.unknown("ログインに失敗しました"))
                        }
                    }
                }
            }
            return result.user
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }
    
    // MARK: - Password Reset
    
    func resetPassword(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
        } catch let error {
            throw AuthError.unknown(error.localizedDescription)
        }
    }
    
    // MARK: - Helper
    
    private func mapFirebaseError(_ error: NSError) -> AuthError {
        if let errorCode = AuthErrorCode(_bridgedNSError: error) {
            switch errorCode.code {
            case .invalidEmail:
                return .invalidEmail
            case .weakPassword:
                return .weakPassword
            case .userNotFound:
                return .userNotFound
            case .wrongPassword:
                return .wrongPassword
            case .emailAlreadyInUse:
                return .emailAlreadyInUse
            case .networkError:
                return .networkError
            default:
                return .unknown(error.localizedDescription)
            }
        }
        return .unknown(error.localizedDescription)
    }
}

