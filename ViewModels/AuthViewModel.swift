//
//  AuthViewModel.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//
// isLoading の変更経路を完全トラッキングするためのログ追加。
// 起動直後に isLoading が true になる原因を特定する目的。

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let authService = AuthService.shared
    private let firestoreService = FirestoreService.shared
    private let persistence = Persistence.shared

    private var authStateHandle: AuthStateDidChangeListenerHandle?

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

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    self?.currentUser = User(
                        id: user.uid,
                        email: user.email,
                        displayName: user.displayName
                    )
                    self?.isAuthenticated = true
                } else {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                }
            }
        }
    }

    /// メッセージをクリアする
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async {
        setLoading(true, "signUp start")
        errorMessage = nil
        successMessage = nil
        defer { setLoading(false, "signUp end") }

        do {
            _ = try await authService.signUp(email: email, password: password)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "登録に失敗しました"
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        setLoading(true, "signIn start")
        errorMessage = nil
        successMessage = nil
        defer { setLoading(false, "signIn end") }

        do {
            _ = try await authService.signIn(email: email, password: password)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "ログインに失敗しました"
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async {
        setLoading(true, "Google start")
        errorMessage = nil
        successMessage = nil
        defer { setLoading(false, "Google end") }

        do {
            _ = try await authService.signInWithGoogle()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Googleログインに失敗しました"
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async -> Bool {
        setLoading(true, "resetPassword start")
        errorMessage = nil
        successMessage = nil
        defer { setLoading(false, "resetPassword end") }

        do {
            try await authService.resetPassword(email: email)
            successMessage = "パスワードリセットメールを送信しました"
            return true
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
