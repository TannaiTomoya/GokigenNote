//
//  MainTabView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = GokigenViewModel()
    
    var body: some View {
        TabView {
            // 今日の問い
            TodayView(vm: vm)
                .tabItem {
                    Label("今日の問い", systemImage: "square.and.pencil")
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
            SettingsView(vm: vm)
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

