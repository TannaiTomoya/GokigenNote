//
//  SettingsView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: GokigenViewModel
    @ObservedObject var authVM: AuthViewModel
    @StateObject private var premium = PremiumManager.shared
    @State private var exportText: String = ""
    @State private var isSharePresented = false
    @State private var showDeleteAlert = false
    @State private var showSignOutAlert = false
    
    var body: some View {
        NavigationStack {
            List {
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

                // プレミアム（Root の sheet で同じ PaywallView を表示）
                Section {
                    Button {
                        PaywallCoordinator.shared.present()
                    } label: {
                        HStack {
                            Label("プレミアム", systemImage: "crown.fill")
                            Spacer()
                            Text(premium.remainingRewriteQuotaText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("課金")
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
                
                // アプリ情報セクション
                Section("アプリ情報") {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // プライバシーセクション
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("プライバシーについて")
                            .font(.headline)
                        Text("ログイン後、データはFirestoreクラウドに保存されます。「言い換えをつくる」等の機能利用時は、入力テキストがGoogleのAI（Gemini API）に送信され、処理後に結果が返ります。送信データはGoogleのプライバシーポリシーに従って取り扱われます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("プライバシー")
                }
                
                // 重要な注意事項
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
                
                // ログアウトセクション
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

