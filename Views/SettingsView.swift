//
//  SettingsView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Combine
import SwiftUI
import UIKit
import FirebaseAuth

struct SettingsView: View {
    @ObservedObject var vm: GokigenViewModel
    @ObservedObject var authVM: AuthViewModel
    @StateObject private var premium = PremiumManager.shared
    @State private var exportText: String = ""
    @State private var isSharePresented = false
    @State private var showDeleteAlert = false
    @State private var showSignOutAlert = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showAuthView = false

    var body: some View {
        NavigationStack {
            List {
                // 未ログイン時: ログインボタン（AuthView へ）
                if !authVM.isAuthenticated {
                    Section {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showAuthView = true
                        } label: {
                            Label("ログイン", systemImage: "person.crop.circle.badge.plus")
                        }
                    } header: {
                        Text("アカウント")
                    } footer: {
                        Text("ログインすると記録をクラウドに保存できます。")
                    }
                }

                // ユーザー情報セクション
                if let user = authVM.currentUser {
                    Section {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName ?? "ユーザー")
                                    .font(.headline)
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("アカウント")
                    }
                }

                // ログアウト（画面上部に表示して見つけやすくする）
                if authVM.isAuthenticated {
                    Section {
                        Button(role: .destructive, action: { showSignOutAlert = true }) {
                            HStack {
                                Spacer()
                                Text("ログアウト")
                                Spacer()
                            }
                        }
                    }
                }

                // プレミアム（Root の sheet で同じ PaywallView を表示）
                Section {
                    Button {
                        PaywallCoordinator.shared.present()
                    } label: {
                        HStack {
                            Label("プレミアム", systemImage: "crown.fill")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(premium.remainingRewriteQuotaText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !premium.entitlementsLoaded {
                                    Text("状態確認中…")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("課金")
                } footer: {
                    if premium.effectivePlan.isYearly {
                        Text("年額プラン：優先処理・待ち時間ゼロ")
                    }
                    Text("タップでプレミアムの申し込み・復元ができます。")
                }

                // データ管理セクション
                Section {
                    Button(action: prepareExport) {
                        Label("データを書き出す", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.entries.isEmpty)

                    Button(role: .destructive, action: { showDeleteAlert = true }) {
                        Label("すべてのデータを削除", systemImage: "trash")
                    }
                    .disabled(vm.entries.isEmpty)
                } header: {
                    Text("データ管理")
                } footer: {
                    Text("データを書き出すと、すべての記録をJSON形式で共有できます。")
                }

                // 統計情報セクション
                Section("統計情報") {
                    HStack {
                        Text("総記録数")
                        Spacer()
                        Text("\(vm.entries.count)件")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("連続記録日数")
                        Spacer()
                        Text("\(vm.trendSnapshot.consecutiveDays)日")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("平均スコア")
                        Spacer()
                        Text(String(format: "%.1f", vm.trendSnapshot.averageScore))
                            .foregroundStyle(.secondary)
                    }
                }

                // 利用規約・プライバシー
                Section {
                    Button { showTerms = true } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    Button { showPrivacy = true } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                } header: {
                    Text("法的情報")
                }

                // 免責
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ 重要")
                            .font(.headline)
                        Text("このアプリはメンタルヘルスの専門的なサポートを提供するものではありません。深刻な悩みがある場合は、専門機関にご相談ください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // 匿名のときはメール/Googleログインを出せる
                if case .anonymous = authVM.authState {
                    Section {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showAuthView = true
                        } label: {
                            Label("メールでログイン", systemImage: "envelope")
                        }
                    } header: {
                        Text("アカウント")
                    } footer: {
                        Text("ログイン後、データはFirestoreクラウドに保存されます。「言い換えをつくる」等の機能利用時は、入力テキストがGoogleのAI（Gemini API）に送信され、処理後に結果が返ります。送信データはGoogleのプライバシーポリシーに従って取り扱われます。")
                    }
                }
            }
            .navigationTitle("設定")
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(activityItems: [exportText])
        }
        .alert("すべてのデータを削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("この操作は取り消せません。本当にすべての記録を削除しますか？")
        }
        .alert("ログアウト", isPresented: $showSignOutAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("ログアウト", role: .destructive) {
                authVM.signOut()
            }
        } message: {
            Text("ログアウトしてもよろしいですか？")
        }
        .sheet(isPresented: $showTerms) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showAuthView) {
            AuthView(authVM: authVM)
        }
    }

    // MARK: - Helper Functions

    private func prepareExport() {
        guard let json = vm.exportEntriesJSON() else { return }
        exportText = json
        isSharePresented = true
    }

    private func deleteAllData() {
        vm.deleteAllEntries()
    }
}

