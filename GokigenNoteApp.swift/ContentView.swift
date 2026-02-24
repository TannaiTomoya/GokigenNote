//
//  ContentView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Today View (今日の問い画面)

struct TodayView: View {
    @ObservedObject var vm: GokigenViewModel
    @StateObject private var premium = PremiumManager.shared
    @StateObject private var speechInput = SpeechInputService()
    @State private var showCopyToast = false
    @State private var shareItem: ShareItem?
    @State private var showSpeechPermissionAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    sceneCard
                    mainVoiceCard
                    if !vm.reformulatedText.isEmpty {
                        resultCard
                    }
                    inputCard
                    actionRow
                    DisclosureGroup("詳しく設定") {
                        VStack(spacing: 12) {
                            moodCard
                            questionCard
                            reformulationContextCard
                        }
                        .padding(.vertical, 8)
                    }
                    Text("AI枠: \(premium.remainingRewriteQuotaText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = premium.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    if let error = vm.lastSaveError {
                        Text("保存に失敗: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    TrendCard(snapshot: vm.trendSnapshot)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ごきげんノート")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(toastOverlay, alignment: .bottom)
            .alert("音声認識を利用できません", isPresented: $showSpeechPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("設定でマイクと音声認識を許可してください。")
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item.text])
        }
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let success = vm.lastSuccessMessage {
                ToastBanner(message: success, style: .success)
            } else if let error = vm.lastErrorMessage {
                ToastBanner(message: error, style: .error)
            } else if showCopyToast {
                ToastBanner(message: "コピーしました", style: .success)
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
                .buttonStyle(BorderedProminentButtonStyle())
                .accessibilityHint("別の問いを表示します")
            }
        }
    }

    /// ① 場面（だけ選ぶ → 即話す）
    private var sceneCard: some View {
        cardContainer {
            Picker("場面", selection: $vm.selectedScene) {
                ForEach(ReformulationScene.allCases) { scene in
                    Text(scene.displayName).tag(scene)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// ② 主役：話す → 整う
    private var mainVoiceCard: some View {
        cardContainer {
            VStack(spacing: 16) {
                Text("言いたいこと、整えて返します")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    toggleVoiceInput()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: speechInput.state == .recording ? "stop.circle.fill" : "mic.fill")
                            .font(.title)
                        Text(speechInput.state == .recording ? "停止" : "話す")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(speechInput.state == .recording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(speechInput.state == .recording ? .red : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(speechInput.state == .processing)
                .accessibilityLabel(speechInput.state == .recording ? "音声入力を停止" : "話す")
                if speechInput.state == .recording && !speechInput.recognizedText.isEmpty {
                    Text(speechInput.recognizedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 結果エリア（before/after ＋ 次の一手：送る・もう一度調整）
    private var resultCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("そのまま使える")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)

                if !vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("入力")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("出力")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(vm.reformulatedText)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 12) {
                    Button {
                        copyReformulatedText()
                        vm.lastSuccessMessage = "コピーしました。LINEなどに貼って送れます"
                    } label: {
                        Label("送る（LINE想定）", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())

                    Button {
                        vm.clearReformulatedResult()
                    } label: {
                        Label("もう一度調整", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }

                HStack(spacing: 8) {
                    Button(action: { SpeechPlayer.shared.speak(vm.reformulatedText) }) {
                        Label("再生", systemImage: "speaker.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(vm.reformulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    switch vm.autoSaveState {
                    case .idle, .saved:
                        Button(action: vm.saveCurrentEntry) {
                            Label("記録する", systemImage: "bookmark")
                                .font(.caption)
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(
                            vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || vm.isAutoSaving
                        )
                    case .saving:
                        Text("保存中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed:
                        Button(action: vm.retryAutoSave) {
                            Label("再送", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }

                if !premium.effectivePlan.isPremium {
                    Button {
                        PaywallCoordinator.shared.present()
                    } label: {
                        HStack {
                            Text("この表現、もっと良くできます（プレミアム）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    /// 感情（状態）・詳しく設定用
    private var moodCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("今の気分")
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

    /// 伝え方の詳細（目的・相手・トーン）
    private var reformulationContextCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("伝え方")
                    .font(.headline)
                Group {
                    HStack {
                        Text("目的")
                            .frame(width: 56, alignment: .leading)
                        Picker("目的", selection: $vm.reformulationPurpose) {
                            ForEach(ReformulationPurpose.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("相手")
                            .frame(width: 56, alignment: .leading)
                        Picker("相手", selection: $vm.reformulationAudience) {
                            ForEach(ReformulationAudience.allCases) { a in
                                Text(a.rawValue).tag(a)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("トーン")
                            .frame(width: 56, alignment: .leading)
                        Picker("トーン", selection: $vm.reformulationTone) {
                            ForEach(ReformulationTone.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    /// 入力（書く場合）
    private var inputCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("書いて整える")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if vm.draftText.isEmpty {
                        Text("入力 or 上で「話す」")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)
                    }
                    TextEditor(text: $vm.draftText)
                        .frame(minHeight: 80)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: vm.insertMicExample) {
                Label("例文を挿入", systemImage: "text.append")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
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
            .buttonStyle(BorderedProminentButtonStyle())
            .disabled(
                vm.isLoadingReformulation
                    || vm.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityHint("入力文をより綺麗に言語化します")
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

    // MARK: - Helper Functions

    private func toggleVoiceInput() {
        switch speechInput.state {
        case .recording:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                let text = await speechInput.stopRecording()
                if !text.isEmpty {
                    vm.applySpeechInput(text)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    vm.reformulateText()
                }
            }
        case .denied, .restricted:
            showSpeechPermissionAlert = true
        case .processing, .transcribing:
            return
        case .notDetermined, .idle, .authorized, .completed:
            Task {
                await speechInput.startRecording()
            }
        case .error:
            showSpeechPermissionAlert = true
        }
    }

    private func copyReformulatedText() {
        UIPasteboard.general.string = vm.reformulatedText
        showCopyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopyToast = false
        }
    }

    private func shareReformulatedText() {
        guard !vm.reformulatedText.isEmpty else { return }
        shareItem = ShareItem(text: vm.reformulatedText)
    }
}

// MARK: - Share Item

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Sheet (旧版 - 削除予定)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems, applicationActivities: applicationActivities)
        controller.excludedActivityTypes = [.assignToContact]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - History Row

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
        .accessibilityLabel(
            "\(entry.date.formatted(date: .abbreviated, time: .omitted))の記録。気分は\(entry.mood.label)。\(entry.originalText)"
        )
    }
}

// MARK: - Trend Card

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
        .accessibilityLabel(
            "最近の傾向。平均スコアは\(String(format: "%.1f", snapshot.averageScore))。\(snapshot.feedback)")
    }
}

// MARK: - Toast Banner

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
            Image(
                systemName: style == .success
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
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
