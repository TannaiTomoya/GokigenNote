//
//  AuthView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPasswordReset = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    headerSection
                    
                    // フォーム
                    formSection
                    
                    // ボタン
                    buttonSection
                    
                    // 切り替え
                    toggleSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isSignUp ? "新規登録" : "ログイン")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(authVM.isLoading)
            .sheet(isPresented: $showPasswordReset) {
                PasswordResetView(authVM: authVM)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Text("ごきげんノート")
                .font(.largeTitle.weight(.bold))
            
            Text("あなたの日々の気持ちを記録")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
    
    private var formSection: some View {
        VStack(spacing: 16) {
            // メールアドレス
            VStack(alignment: .leading, spacing: 8) {
                Text("メールアドレス")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("example@email.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
            }
            
            // パスワード
            VStack(alignment: .leading, spacing: 8) {
                Text("パスワード")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("6文字以上", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isSignUp ? .newPassword : .password)
            }
            
            // パスワード確認（新規登録時のみ）
            if isSignUp {
                VStack(alignment: .leading, spacing: 8) {
                    Text("パスワード（確認）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("もう一度入力", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                }
            }
            
            // エラーメッセージ
            if let error = authVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var buttonSection: some View {
        VStack(spacing: 12) {
            // メール＋パスワード
            Button(action: handleEmailAuth) {
                HStack {
                    if authVM.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSignUp ? "登録" : "ログイン")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || authVM.isLoading)
            
            // Google Sign In
            Button(action: { Task { await authVM.signInWithGoogle() } }) {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Googleでログイン")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authVM.isLoading)
            
            // パスワードリセット（ログイン時のみ）
            if !isSignUp {
                Button("パスワードを忘れた場合") {
                    showPasswordReset = true
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    private var toggleSection: some View {
        Button(action: { isSignUp.toggle() }) {
            Text(isSignUp ? "アカウントをお持ちの方はこちら" : "新規登録はこちら")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }
    
    private var isFormValid: Bool {
        let emailValid = !email.isEmpty && email.contains("@")
        let passwordValid = password.count >= 6
        
        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        } else {
            return emailValid && passwordValid
        }
    }
    
    private func handleEmailAuth() {
        Task {
            if isSignUp {
                await authVM.signUp(email: email, password: password)
            } else {
                await authVM.signIn(email: email, password: password)
            }
        }
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("パスワードリセット用のメールを送信します")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("メールアドレス")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("example@email.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                
                Button(action: {
                    Task {
                        await authVM.resetPassword(email: email)
                        dismiss()
                    }
                }) {
                    Text("送信")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || !email.contains("@"))
                
                Spacer()
            }
            .padding()
            .navigationTitle("パスワードリセット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

