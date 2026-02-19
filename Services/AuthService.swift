//
//  AuthService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore

/// OAuth 認証画面の表示用。UIViewController を AuthUIDelegate として渡すためのラッパー
private final class AuthUIViewControllerDelegate: NSObject, AuthUIDelegate {
    weak var viewController: UIViewController?

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        viewController?.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)?) {
        viewController?.dismiss(animated: flag, completion: completion)
    }
}

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

        // スコープの設定
        provider.scopes = ["email", "profile"]

        // カスタムパラメータ
        provider.customParameters = [
            "prompt": "select_account"
        ]

        // ルートViewControllerを取得（OAuth認証画面の提示に必要）
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            throw AuthError.unknown("認証画面を表示できません")
        }

        do {
            let uiDelegate = AuthUIViewControllerDelegate(viewController: rootViewController)
            let credential = try await provider.credential(with: uiDelegate)
            let result = try await Auth.auth().signIn(with: credential)
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

