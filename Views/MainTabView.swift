//
//  MainTabView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = GokigenViewModel()
    @StateObject private var trainingVM = TrainingViewModel()
    @StateObject private var network = NetworkMonitor()
    @ObservedObject var authVM: AuthViewModel

    var body: some View {
        TabView {
            // 今日の問い
            TodayView(vm: vm)
                .tabItem {
                    Label("今日の問い", systemImage: "square.and.pencil")
                }

            // トレーニング
            TrainingView(vm: trainingVM, gokigenVM: vm)
                .tabItem {
                    Label("トレーニング", systemImage: "brain.head.profile")
                }

            // カレンダー
            CalendarView(vm: vm)
                .tabItem {
                    Label("カレンダー", systemImage: "calendar")
                }

            // 最近の記録
            HistoryListView(vm: vm)
                .tabItem {
                    Label("記録", systemImage: "book")
                }

            // 設定
            SettingsView(vm: vm, authVM: authVM)
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
        .task(id: authVM.currentUser?.id) {
            guard let userId = authVM.currentUser?.id else {
                print("⚠️ userId is nil. skip setUserId")
                return
            }
            print("✅ setUserId:", userId)
            vm.setUserId(userId)
            trainingVM.setUserId(userId)
        }
        .onChange(of: network.isOnline) { _, isOnline in
            guard isOnline else { return }
            vm.flushPending()
        }
    }
}

