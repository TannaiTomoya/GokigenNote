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
            // 地雷LINEストッパー
            LineStopperRootView(authVM: authVM)
                .tabItem {
                    Label("地雷LINE", systemImage: "bubble.left.and.bubble.right")
                }

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
        .onAppear {
            vm.authViewModel = authVM
        }
        .task(id: authVM.uid ?? "nil") {
            guard let uid = authVM.uid else {
                await PremiumManager.shared.setCurrentUserId(nil)
                vm.clearUserId()
                trainingVM.clearUserId()
                return
            }
            print("✅ setUserId:", uid)
            await PremiumManager.shared.setCurrentUserId(uid)
            vm.authViewModel = authVM
            vm.setUserId(uid)
            trainingVM.setUserId(uid)
        }
        .onChange(of: authVM.uid) { _, newUID in
            if let uid = newUID {
                Task { await PremiumManager.shared.setCurrentUserId(uid) }
                vm.setUserId(uid)
                trainingVM.setUserId(uid)
            } else {
                Task { await PremiumManager.shared.setCurrentUserId(nil) }
                vm.clearUserId()
                trainingVM.clearUserId()
            }
        }
        .onChange(of: network.isOnline) { _, isOnline in
            guard isOnline else { return }
            vm.flushPending()
        }
    }
}

