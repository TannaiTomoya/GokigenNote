//
//  ContentView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var vm = GokigenViewModel()
    @State private var exportText: String = ""
    @State private var isSharePresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    questionCard
                    moodCard
                    inputCard
                    actionRow
                    historySection
                    TrendCard(snapshot: vm.trendSnapshot)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ごきげんノート")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(toastOverlay, alignment: .bottom)
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(activityItems: [exportText])
        }
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let success = vm.lastSuccessMessage {
                ToastBanner(message: success, style: .success)
            } else if let error = vm.lastErrorMessage {
                ToastBanner(message: error, style: .error)
            }
        }
        .padding(.horizontal)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ごきげんノート")
                .font(.largeTitle.weight(.bold))
            Text("今の自分に一言かけるなら？")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var questionCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("今日の問い")
                    .font(.headline)
                Text(vm.currentPrompt)
                    .font(.title3.weight(.semibold))
                Button(action: vm.newPrompt) {
                    Text("問いを変える")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("別の問いを表示します")
            }
        }
    }

    private var moodCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("今日の気分")
                    .font(.headline)
                Picker("気分", selection: $vm.selectedMood) {
                    ForEach(Mood.allCases) { mood in
                        Text(mood.emoji)
                            .accessibilityLabel(mood.label)
                            .tag(mood)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var inputCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("感じたことを書く")
                    .font(.headline)
                ZStack(alignment: .topLeading) {
                    if vm.draftText.isEmpty {
                        Text("今日は何が一番心に残った？")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)
                    }
                    TextEditor(text: $vm.draftText)
                        .frame(minHeight: 150)
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .accessibilityHint("感じたことを自由に入力できます")
                }
                
                // 言語化された文章を表示
                if !vm.reformulatedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        Text("言い換え")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(vm.reformulatedText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Button(action: vm.saveCurrentEntry) {
                    Text("この一言を記録する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("今の気持ちを履歴に残します")
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: vm.insertMicExample) {
                Label("例文を挿入", systemImage: "text.append")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("いまの気持ちに近い例文を差し込みます")

            Button(action: { vm.reformulateText() }) {
                HStack {
                    if vm.isLoadingReformulation {
                        ProgressView()
                        Text("考え中…")
                    } else {
                        Text("言い換えをつくる")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoadingReformulation || vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("入力文をより綺麗に言語化します")
        }
    }

    private var historySection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近の記録")
                    .font(.headline)
                if vm.recentEntries.isEmpty {
                    Text("まだ記録がありません。今日の一言から始めてみましょう。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.recentEntries) { entry in
                        HistoryRow(entry: entry)
                    }
                }
                NavigationLink {
                    HistoryListView(vm: vm)
                } label: {
                    Text("すべての記録を見る")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("過去の記録一覧に移動します")

                if !vm.recentEntries.isEmpty {
                    Button(action: prepareExport) {
                        Label("データを書き出す", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("記録をJSONとして共有します")
                }
            }
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Export Helpers

private extension ContentView {
    func prepareExport() {
        guard let json = vm.exportEntriesJSON() else { return }
        exportText = json
        isSharePresented = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.excludedActivityTypes = [.assignToContact]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct HistoryRow: View {
    let entry: Entry

    var body: some View {
        HStack {
            Text(entry.mood.emoji)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.originalText)
                    .font(.body)
                    .lineLimit(2)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.date.formatted(date: .abbreviated, time: .omitted))の記録。気分は\(entry.mood.label)。\(entry.originalText)")
    }
}

struct TrendCard: View {
    let snapshot: TrendSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近のトレンド")
                .font(.headline)
            HStack(spacing: 16) {
                Text(snapshot.dominantEmoji)
                    .font(.system(size: 48))
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均スコア \(String(format: "%.1f", snapshot.averageScore))")
                        .font(.body)
                    Text(snapshot.feedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.3), value: snapshot.dominantEmoji)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("最近の傾向。平均スコアは\(String(format: "%.1f", snapshot.averageScore))。\(snapshot.feedback)")
    }
    }

struct ToastBanner: View {
    enum Style {
        case success, error
        var background: Color {
            switch self {
            case .success: return Color.green.opacity(0.15)
            case .error: return Color.orange.opacity(0.15)
            }
        }
        var tint: Color {
            switch self {
            case .success: return .green
            case .error: return .orange
            }
        }
    }
    
    let message: String
    let style: Style
    
    var body: some View {
        HStack {
            Image(systemName: style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(style.tint)
            Text(message)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(style.background, in: RoundedRectangle(cornerRadius: 16))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        //.accessibilityLiveRegion(AccessibilityLiveRegion.assertive)
    }
}
