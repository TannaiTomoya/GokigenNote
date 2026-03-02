//
//  HistoryView.swift
//  GokigenNote
//
//  地雷ストッパー履歴一覧・傾向カード。
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var authVM: AuthViewModel
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                controls
                InsightsCard(insights: vm.insights)

                List {
                    ForEach(vm.filtered()) { r in
                        NavigationLink {
                            HistoryDetailView(authVM: authVM, record: r)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    RiskBadge(risk: r.risk)
                                    Spacer()
                                    Text(r.createdDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(r.oneLiner)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)

                                if let label = r.selectedLabel {
                                    Text("コピー: \(label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding(.horizontal)
            .navigationTitle("履歴")
            .onAppear {
                if let uid = authVM.uid {
                    vm.start(uid: uid)
                }
            }
            .onChange(of: authVM.uid) { _, newUid in
                if let uid = newUid {
                    vm.start(uid: uid)
                } else {
                    vm.stop()
                }
            }
            .onChange(of: vm.days) { _, _ in vm.recomputeInsights() }
            .onChange(of: vm.riskFilter) { _, _ in vm.recomputeInsights() }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("期間", selection: $vm.days) {
                Text("7日").tag(7)
                Text("30日").tag(30)
                Text("90日").tag(90)
            }
            .pickerStyle(.segmented)

            Menu {
                Button("すべて") { vm.riskFilter = nil }
                Button("LOW") { vm.riskFilter = .low }
                Button("MEDIUM") { vm.riskFilter = .medium }
                Button("HIGH") { vm.riskFilter = .high }
            } label: {
                Text(vm.riskFilter?.rawValue ?? "Risk")
                    .font(.subheadline)
            }
        }
    }
}
