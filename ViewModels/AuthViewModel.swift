//
//  AuthViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

/// 認証プロセス結果（UIは即描画、この状態でボタン制御）
enum AuthState: Equatable {
    case unknown
    case inProgress
    case signedOut
    case signedIn(uid: String)
    case anonymous(uid: String)
    case failed(message: String)

    var uid: String? {
        switch self {
        case .signedIn(let uid), .anonymous(let uid): return uid
        default: return nil
        }
    }

    var isUsable: Bool {
        uid != nil
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var authState: AuthState = .unknown
    @Published var currentUser: AppUser?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    /// ユーザーが「ログアウト」を押したとき true。匿名ログインをスキップする
    private var userRequestedSignOut = false

    /// 互換用。authState.uid と同期
    var uid: String? { authState.uid }
    /// 互換用。signedIn / anonymous なら true
    var isAuthenticated: Bool { authState.isUsable }
    /// 互換用。uid が取れる状態なら true（AuthGate / MainTabView 用）
    var authReady: Bool { authState.isUsable }

    private let authService = AuthService.shared
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var ensuredUserDocUID: String?
    /// 匿名ログインの多重実行防止
    private var anonymousSignInTask: Task<Void, Never>?

    private static let anonymousBackoffSeconds: [UInt64] = [1, 2, 4]
    private static let anonymousMaxTries = 3

    init() {
        setupAuthStateListener()
    }

    private func setLoading(_ value: Bool, _ note: String = "") {
        isLoading = value
        print("🔄 isLoading=\(value) \(note)")
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user {
                    self.currentUser = AppUser(
                        id: user.uid,
                        email: user.email,
                        displayName: user.displayName
                    )
                    self.authState = user.isAnonymous ? .anonymous(uid: user.uid) : .signedIn(uid: user.uid)
                    self.userRequestedSignOut = false
                    PremiumManager.shared.setCurrentUserId(user.uid)

                    if self.ensuredUserDocUID != user.uid {
                        self.ensuredUserDocUID = user.uid
                        do {
                            try await FirestoreService.shared.ensureUserDoc(
                                uid: user.uid,
                                email: user.email,
                                displayName: user.displayName
                            )
                        } catch {
                            print("[AuthViewModel] ensureUserDoc failed: \(error)")
                        }
                    }
                } else {
                    self.currentUser = nil
                    self.ensuredUserDocUID = nil
                    PremiumManager.shared.setCurrentUserId(nil)
                    if self.userRequestedSignOut {
                        self.userRequestedSignOut = false
                        self.authState = .signedOut
                    } else {
                        self.startAnonymousSignInIfNeeded()
                    }
                }
            }
        }
    }

    /// 匿名ログインを1本化。既に実行中 or 既にユーザーがいれば何もしない
    private func startAnonymousSignInIfNeeded() {
        guard Auth.auth().currentUser == nil else { return }
        guard anonymousSignInTask == nil else { return }
        authState = .inProgress
        anonymousSignInTask = Task { [weak self] in
            guard let self else { return }
            await self.tryAnonymousWithBackoff()
            await MainActor.run { self.anonymousSignInTask = nil }
        }
    }

    /// 指数バックオフで匿名ログイン（1s→2s→4s、最大3回）。失敗時は authState = .failed
    private func tryAnonymousWithBackoff() async {
        for (index, delaySec) in Self.anonymousBackoffSeconds.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
            }
            do {
                _ = try await Auth.auth().signInAnonymously()
                return
            } catch {
                print("[AuthViewModel] signInAnonymously attempt \(index + 1) failed: \(error)")
            }
        }
        authState = .failed(message: "接続を確認して再試行してください。")
    }

    /// 匿名ログイン失敗後の「再試行」ボタン用
    func retryAnonymous() async {
        startAnonymousSignInIfNeeded()
    }

    /// callable 実行前に呼ぶ。匿名ログインが未完了なら同じ1本のタスクを叩く（連打対策）
    func ensureUserBeforeCallable() async {
        startAnonymousSignInIfNeeded()
    }

    // MARK: - Utilities

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private struct TimeoutError: Error {}

    /// await が帰ってこない事故対策（Googleログインで起きがち）
    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async {
        if isLoading { return }
        setLoading(true, "signUp start")
        clearMessages()
        defer { setLoading(false, "signUp end") }

        do {
            _ = try await withTimeout(seconds: 20) {
                try await self.authService.signUp(email: email, password: password)
            }
            successMessage = "登録しました"
        } catch is TimeoutError {
            errorMessage = "処理がタイムアウトしました（通信状況を確認してください）"
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "登録に失敗しました"
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        if isLoading { return }
        setLoading(true, "signIn start")
        clearMessages()
        defer { setLoading(false, "signIn end") }

        do {
            _ = try await withTimeout(seconds: 20) {
                try await self.authService.signIn(email: email, password: password)
            }
            successMessage = "ログインしました"
        } catch is TimeoutError {
            errorMessage = "処理がタイムアウトしました（通信状況を確認してください）"
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "ログインに失敗しました"
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async {
        if isLoading { return }
        setLoading(true, "Google start")
        clearMessages()
        defer { setLoading(false, "Google end") }

        do {
            _ = try await withTimeout(seconds: 30) {
                try await self.authService.signInWithGoogle()
            }
            successMessage = "Googleでログインしました"
        } catch is TimeoutError {
            errorMessage = "Googleログインがタイムアウトしました（画面が出ない/閉じない可能性）"
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Googleログインに失敗しました"
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async -> Bool {
        if isLoading { return false }
        setLoading(true, "resetPassword start")
        clearMessages()
        defer { setLoading(false, "resetPassword end") }

        do {
            try await withTimeout(seconds: 20) {
                try await self.authService.resetPassword(email: email)
            }
            successMessage = "パスワードリセットメールを送信しました"
            return true
        } catch is TimeoutError {
            errorMessage = "処理がタイムアウトしました（通信状況を確認してください）"
            return false
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = "送信に失敗しました"
            return false
        }
    }

    // MARK: - Sign Out

    func signOut() {
        userRequestedSignOut = true
        do {
            try authService.signOut()
        } catch {
            userRequestedSignOut = false
            errorMessage = "ログアウトに失敗しました"
        }
    }
}
