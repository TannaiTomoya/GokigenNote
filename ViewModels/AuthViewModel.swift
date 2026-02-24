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

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var authReady = false
    @Published private(set) var uid: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let authService = AuthService.shared
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    /// セッション復元でも ensureUserDoc を1回だけ叩くための重複防止
    private var ensuredUserDocUID: String?

    init() {
        print("✅ AuthViewModel init. isLoading=\(isLoading)")
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

    // MARK: - Auth State Listener（確定前にDBを触らない＝authReady でゲート）

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.uid = user?.uid
                if let user {
                    self.currentUser = User(
                        id: user.uid,
                        email: user.email,
                        displayName: user.displayName
                    )
                    self.isAuthenticated = true
                } else {
                    self.currentUser = nil
                    self.isAuthenticated = false
                    self.ensuredUserDocUID = nil
                }
                self.authReady = true

                // セッション復元でも必ず user doc を用意（idempotent・重複防止）
                if let u = user, self.ensuredUserDocUID != u.uid {
                    self.ensuredUserDocUID = u.uid
                    do {
                        try await FirestoreService.shared.ensureUserDoc(
                            uid: u.uid,
                            email: u.email,
                            displayName: u.displayName
                        )
                    } catch {
                        print("[AuthViewModel] ensureUserDoc failed: \(error)")
                    }
                }
            }
        }
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
        do {
            try authService.signOut()
        } catch {
            errorMessage = "ログアウトに失敗しました"
        }
    }
}
