//
//  AuthViewModel.swift
//  GokigenNote
//
//  認証状態の管理。ログアウト時は userRequestedSignOut を立て、匿名ログインを再実行しない。
//

import Combine
import Foundation
import SwiftUI
import FirebaseAuth

enum AuthState: Equatable {
    case unknown
    case inProgress
    case signedIn
    case anonymous
    case signedOut
    case failed(String)
}

final class AuthViewModel: ObservableObject {
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var uid: String?
    @Published private(set) var currentUser: FirebaseAuth.User?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var isLoading = false

    /// ユーザーが明示的にログアウトしたとき true。このときは匿名ログインを再実行しない。
    private var userRequestedSignOut = false

    private let authService = AuthService.shared
    private var authListener: AuthStateDidChangeListenerHandle?

    var isAuthenticated: Bool { currentUser != nil }
    /// Firestore 等を叩いてよいか（認証が確定しているか）
    var authReady: Bool {
        switch authState {
        case .signedIn, .anonymous: return true
        default: return false
        }
    }

    init() {
        FirebaseManager.shared.configure()
        addAuthStateListener()
    }

    deinit {
        if let handle = authListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func addAuthStateListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                self?.handleAuthChange(user: firebaseUser)
            }
        }
    }

    @MainActor
    private func handleAuthChange(user: FirebaseAuth.User?) {
        if let user = user {
            userRequestedSignOut = false
            uid = user.uid
            currentUser = user
            authState = user.isAnonymous ? .anonymous : .signedIn
            return
        }

        uid = nil
        currentUser = nil

        if userRequestedSignOut {
            authState = .signedOut
            return
        }

        Task { await trySignInAnonymously() }
    }

    @MainActor
    private func trySignInAnonymously() async {
        authState = .inProgress
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let result = try await Auth.auth().signInAnonymously()
                uid = result.user.uid
                currentUser = result.user
                authState = .anonymous
                return
            } catch {
                print("[AuthViewModel] signInAnonymously attempt \(attempt) failed:", error)
                lastError = error
            }
        }
        authState = .failed(lastError?.localizedDescription ?? "匿名ログインに失敗しました")
    }

    @MainActor
    func signOut() {
        userRequestedSignOut = true
        do {
            try authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
            userRequestedSignOut = false
        }
    }

    @MainActor
    func signUp(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        successMessage = nil
        do {
            _ = try await authService.signUp(email: email, password: password)
            successMessage = "登録できました"
        } catch let e as AuthError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        successMessage = nil
        do {
            _ = try await authService.signIn(email: email, password: password)
            successMessage = "ログインしました"
        } catch let e as AuthError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        successMessage = nil
        do {
            _ = try await authService.signInWithGoogle()
            successMessage = "ログインしました"
        } catch let e as AuthError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func resetPassword(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await authService.resetPassword(email: email)
            return true
        } catch let e as AuthError {
            errorMessage = e.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 匿名ログインに失敗した状態から再試行（userRequestedSignOut は触らない）
    @MainActor
    func retryAnonymous() async {
        guard !userRequestedSignOut else { return }
        await trySignInAnonymously()
    }

    /// 呼び出し元が Callable 等を叩く前に、未ログインなら匿名ログインを試みる
    @MainActor
    func ensureUserBeforeCallable() async {
        if currentUser != nil { return }
        if userRequestedSignOut { return }
        await trySignInAnonymously()
    }

    @MainActor
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
