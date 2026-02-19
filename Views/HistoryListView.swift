//
//  HistoryListView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import SwiftUI

struct HistoryListView: View {
    @ObservedObject var vm: GokigenViewModel
    @State private var selectedEntry: Entry?

    var body: some View {
        List {
            if vm.entries.isEmpty {
                ContentUnavailableView {
                    Label("まだ記録がありません", systemImage: "square.and.pencil")
                } description: {
                    Text("今日の気持ちを一言だけ残してみましょう。")
                }
            } else {
                ForEach(vm.entries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        HistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
                if vm.canLoadMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { vm.loadMore() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("すべての記録")
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
        }
    }
}

