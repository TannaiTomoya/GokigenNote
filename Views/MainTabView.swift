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
    @ObservedObject private var paywallCoordinator = PaywallCoordinator.shared

    var body: some View {
        TabView {
            // 地雷LINEストッパー
            LineStopperRootView(authVM: authVM, onSaveDraft: { text in vm.draftText = text })
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
        .sheet(isPresented: Binding(
            get: { paywallCoordinator.isPresented },
            set: { if !$0 { PaywallCoordinator.shared.dismiss() } }
        )) {
            switch paywallCoordinator.modalKind {
            case .paywall:
                PaywallView()
            case .congestion(let tier, let retryAfter, let retryAction):
                CongestionGateView(
                    tier: tier,
                    retryAfterSeconds: retryAfter,
                    onRetry: {
                        if let action = retryAction {
                            RetryBus.post(action)
                        }
                        PaywallCoordinator.shared.dismiss()
                    },
                    onUpgrade: {
                        PaywallCoordinator.shared.dismiss()
                        PaywallCoordinator.shared.present(preselect: .yearly)
                    },
                    onClose: { PaywallCoordinator.shared.dismiss() }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { paywallCoordinator.isQuotaExceededSheetPresented },
            set: { if !$0 { PaywallCoordinator.shared.dismissQuotaExceeded() } }
        )) {
            QuotaExceededView()
        }
        .sheet(isPresented: Binding(
            get: { paywallCoordinator.isHighUpsellSheetPresented },
            set: { if !$0 { PaywallCoordinator.shared.dismissHighUpsell() } }
        )) {
            HighUpsellSheet()
        }
        .onAppear {
            vm.authViewModel = authVM
        }
        .task(id: authVM.uid ?? "nil") {
            guard let uid = authVM.uid else {
                PremiumManager.shared.setCurrentUserId(nil)
                vm.clearUserId()
                trainingVM.clearUserId()
                return
            }
            print("✅ setUserId:", uid)
            PremiumManager.shared.setCurrentUserId(uid)
            vm.authViewModel = authVM
            vm.setUserId(uid)
            trainingVM.setUserId(uid)
        }
        .onChange(of: authVM.uid) { _, newUID in
            if let uid = newUID {
                PremiumManager.shared.setCurrentUserId(uid)
                vm.setUserId(uid)
                trainingVM.setUserId(uid)
            } else {
                PremiumManager.shared.setCurrentUserId(nil)
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

