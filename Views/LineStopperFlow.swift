//
//  LineStopperFlow.swift
//  GokigenNote
//
//  Drop-in flow: Input → Result → Copy → (optional) Paywall
//  型定義（LineStopperRisk, LineStopperSuggestion）は LineStopperTypes.swift にのみあること。ここに Models を追加すると二重定義でエラーになる。
//

import Combine
import FirebaseAuth
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// MARK: - ViewModel

@MainActor
final class LineStopperViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var risk: LineStopperRisk?
    @Published var riskOneLiner: String?
    @Published var suggestions: [LineStopperSuggestion] = []
    @Published var selectedSuggestion: LineStopperSuggestion?

    @Published var shouldShowPaywall: Bool = false

    /// 5秒以上で混雑UI。年額なら出さない。
    @Published var showQueueOverlay: Bool = false
    @Published var elapsedSeconds: Int = 0
    private var queueTimer: Timer?
    /// 直近チェックの documentID（コピー時に logCopy に渡す）
    private(set) var lastCheckId: String?

    /// HIGH判定時の送信前ロック（Pause）表示
    @Published var showHighGate: Bool = false
    @Published var highGateUnlocking: Bool = false
    /// 直近チェックの queueTier（HIGHゲートの出し分け用。Functions 返却の "priority"|"standard"）
    @Published var lastQueueTier: String = "standard"

    private var hasCancelledWaiting: Bool = false
    private var retryObserver: NSObjectProtocol?

    init() {
        retryObserver = NotificationCenter.default.addObserver(
            forName: RetryBus.retryRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard RetryBus.parseAction(note) == .lineStopper else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.generate()
            }
        }
    }

    deinit {
        if let o = retryObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    func resetResult() {
        risk = nil
        riskOneLiner = nil
        suggestions = []
        selectedSuggestion = nil
        errorMessage = nil
        showHighGate = false
        lastQueueTier = "standard"
    }

    /// 「あとで確認」タップ時。オーバーレイを閉じ、結果は破棄（バックグラウンドの完了は無視）
    func cancelWaiting() {
        hasCancelledWaiting = true
        isLoading = false
        LineStopperRemoteService.shared.resetProgress()
    }

    func startQueueTimer() {
        elapsedSeconds = 0
        showQueueOverlay = false
        queueTimer?.invalidate()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.elapsedSeconds += 1
                if self.elapsedSeconds >= 5 {
                    self.showQueueOverlay = true
                }
            }
        }
        RunLoop.main.add(queueTimer!, forMode: .common)
    }

    func stopQueueTimer() {
        queueTimer?.invalidate()
        queueTimer = nil
        showQueueOverlay = false
    }

    func dismissQueueOverlay() {
        showQueueOverlay = false
    }

    func generate() async {
        errorMessage = nil
        shouldShowPaywall = false
        hasCancelledWaiting = false
        lastCheckId = nil

        if PremiumManager.shared.isFreeTrialEnded {
            shouldShowPaywall = true
            return
        }
        let maxChars = InputLimit.maxCharsLineStopper(isPremium: PremiumManager.shared.effectivePlan.isPremium)
        let trimmed = InputLimit.clampText(inputText, maxChars: maxChars)
        guard !trimmed.isEmpty else {
            errorMessage = "LINE文を貼り付けてください。"
            return
        }

        isLoading = true
        startQueueTimer()
        defer {
            stopQueueTimer()
            isLoading = false
            LineStopperRemoteService.shared.resetProgress()
        }

        do {
            let (riskRaw, oneLiner, suggestionTuples, queueTier, limitsPayload) = try await GeminiService.shared
                .generateLineStopperResult(text: trimmed)

            if hasCancelledWaiting { return }

            if let limits = limitsPayload {
                PremiumManager.shared.applyServerQuotaFromLimits(limits)
            }

            let mappedRisk: LineStopperRisk
            switch riskRaw.uppercased() {
            case "HIGH": mappedRisk = .high
            case "MEDIUM": mappedRisk = .medium
            default: mappedRisk = .low
            }
            risk = mappedRisk
            riskOneLiner = oneLiner.isEmpty ? nil : oneLiner
            suggestions = suggestionTuples.map {
                LineStopperSuggestion(label: $0.label, text: $0.text)
            }
            selectedSuggestion = suggestions.first

            lastQueueTier = queueTier
            // HIGHゲート: queueTier だけで判定（priority なら出さない）
            if mappedRisk == .high && queueTier != "priority" {
                showHighGate = true
            }

            let plan = PremiumManager.shared.effectivePlan.serverPlanValue
            if let uid = Auth.auth().currentUser?.uid {
                let checkId = await LineCheckLogger.shared.logResult(
                    uid: uid,
                    risk: riskRaw.uppercased(),
                    oneLiner: oneLiner,
                    suggestions: suggestionTuples.map { ["label": $0.label, "text": $0.text] },
                    latencyMs: elapsedSeconds * 1000,
                    plan: plan,
                    queueTier: queueTier,
                    waitedMs: elapsedSeconds * 1000
                )
                lastCheckId = checkId
            }
        } catch {
            if hasCancelledWaiting { return }
            if FunctionsErrorExtraction.isFreeTrialEnded(error) {
                shouldShowPaywall = true
                return
            }
            if CongestionGateHandler.presentIfNeeded(
                error: error, op: .lineStopper, payloadKey: trimmed)
            {
                return
            }
            if QuotaService.isUnauthenticated(error) {
                errorMessage = "接続を確認して再試行してください。"
            } else {
                let raw = error.localizedDescription
                let ns = error as NSError
                let isInternal =
                    raw.uppercased().contains("INTERNAL")
                    || (ns.domain == "FunctionsErrorDomain" && ns.code == 13)
                if raw.contains("NOT FOUND") || raw.lowercased().contains("not found")
                    || raw.contains("404") || isInternal
                {
                    errorMessage = "混雑中です。少し待つか、優先でチェックできます。"
                } else if QuotaService.isResourceExhausted(error) {
                    errorMessage = "混雑中です。少し待つか、優先でチェックできます。"
                } else {
                    errorMessage = "混雑中です。少し待つか、優先でチェックできます。"
                }
            }
        }
    }

    func copySelected() {
        guard let text = selectedSuggestion?.text else { return }
        #if os(iOS)
            UIPasteboard.general.string = text
        #endif
        if let uid = Auth.auth().currentUser?.uid,
            let checkId = lastCheckId,
            let suggestion = selectedSuggestion,
            let idx = suggestions.firstIndex(where: { $0.id == suggestion.id })
        {
            Task {
                await LineCheckLogger.shared.logCopy(
                    uid: uid, checkId: checkId, label: suggestion.label, index: idx)
            }
        }
    }

    /// コピー時に呼ぶ（label と index を渡す）。HighResultView 等から使用。
    func recordCopy(label: String, index: Int) {
        guard let uid = Auth.auth().currentUser?.uid, let checkId = lastCheckId else { return }
        Task {
            await LineCheckLogger.shared.logCopy(
                uid: uid, checkId: checkId, label: label, index: index)
        }
    }
}

// MARK: - Root

struct LineStopperRootView: View {
    @StateObject private var vm = LineStopperViewModel()
    @ObservedObject private var pm = PremiumManager.shared
    @ObservedObject private var remote = LineStopperRemoteService.shared
    @ObservedObject var authVM: AuthViewModel
    var onSaveDraft: (String) -> Void = { _ in }

    var body: some View {
        TabView {
            NavigationStack {
                LineStopperInputView(vm: vm, authVM: authVM, onSaveDraft: onSaveDraft)
                    .navigationTitle("地雷LINEストッパー")
                    .navigationBarTitleDisplayMode(.inline)
                    .sheet(isPresented: $vm.shouldShowPaywall) {
                        PaywallView()
                    }
            }
            .tabItem { Label("チェック", systemImage: "checkmark.bubble") }

            HistoryView(authVM: authVM)
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
        }
        .overlay {
            if vm.isLoading {
                LineStopperWaitingGate(
                    queueTier: remote.lastQueueTier.rawValue, isLoading: $vm.isLoading)
            } else if pm.isLoading {
                LoadingOverlay(isLoading: true)
            }
        }
        .overlay {
            if vm.showHighGate {
                HighRiskGateView(
                    queueTier: vm.lastQueueTier,
                    onContinueStandard: { vm.showHighGate = false },
                    onUpgradeYearly: {
                        vm.showHighGate = false
                        PaywallCoordinator.shared.present(preselect: .yearly)
                    }
                )
            }
        }
    }
}

// MARK: - Input Screen

struct LineStopperInputView: View {
    @ObservedObject var vm: LineStopperViewModel
    @ObservedObject var authVM: AuthViewModel
    var onSaveDraft: (String) -> Void = { _ in }

    private var canUseButton: Bool {
        switch authVM.authState {
        case .signedIn, .anonymous: return true
        case .signedOut, .inProgress, .unknown, .failed: return false
        }
    }

    private var buttonLabel: String {
        switch authVM.authState {
        case .inProgress, .unknown: return "準備中…"
        case .failed: return "危険度をチェックする"
        case .signedIn, .anonymous: return "危険度をチェックする"
        case .signedOut: return "ログインしてください"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if case .failed(let message) = authVM.authState {
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("再試行") {
                            Task { await authVM.retryAnonymous() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                TextEditor(text: $vm.inputText)
                    .padding(12)
                    .frame(minHeight: 180)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if vm.inputText.isEmpty {
                            Text("ここにLINEを貼り付け")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                        }
                    }
                Text("入力は最大\(InputLimit.maxCharsLineStopper(isPremium: PremiumManager.shared.effectivePlan.isPremium))文字までです。長文は「要点だけ」残して貼ってください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    Task {
                        await authVM.ensureUserBeforeCallable()
                        guard authVM.uid != nil else {
                            vm.errorMessage = "接続を確認して再試行してください。"
                            return
                        }
                        await vm.generate()
                    }
                } label: {
                    Text(buttonLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !canUseButton || vm.isLoading
                        || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                quotaRow

                Divider().padding(.top, 4)

                if vm.risk == .high {
                    HighResultView(
                        vm: vm,
                        inputText: vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines),
                        onSaveDraft: onSaveDraft
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if vm.risk == .medium {
                    MediumResultView(vm: vm)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if vm.risk == .low {
                    LowResultView(vm: vm)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 8)
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.risk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("そのLINE、あとで後悔するよ")
                .font(.title3.weight(.bold))
            Text("送信前に一回だけ止める。危険度と\u{201C}安全な一言\u{201D}に変換します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quotaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("現在: \(PremiumManager.shared.effectivePlan.displayName)")
                Spacer()
                Text("AI枠: \(PremiumManager.shared.remainingRewriteQuotaText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !PremiumManager.shared.effectivePlan.isPremium {
                Text("無料で1日10回まで利用できます")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Result Section

struct LineStopperResultView: View {
    @ObservedObject var vm: LineStopperViewModel

    var body: some View {
        VStack(spacing: 12) {
            riskCard

            suggestionPicker

            HStack(spacing: 12) {
                Button {
                    vm.copySelected()
                } label: {
                    Text("コピーする")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    vm.resetResult()
                    vm.inputText = ""
                } label: {
                    Text("クリア")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await vm.generate() }
            } label: {
                Text("もう一度チェック")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var riskCard: some View {
        let risk = vm.risk ?? .low
        let oneLiner = vm.riskOneLiner ?? risk.oneLiner
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(risk.emoji) 危険度：\(risk.title)")
                    .font(.headline)
                Spacer()
            }
            Text(oneLiner)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("改善案（3つだけ）")
                .font(.subheadline.weight(.semibold))

            ForEach(vm.suggestions) { s in
                Button {
                    vm.selectedSuggestion = s
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            if vm.selectedSuggestion?.id == s.id {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Image(systemName: "circle")
                            }
                        }
                        Text(s.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 待機オーバーレイ（Service の progress と完全同期）

enum WaitingPhase {
    case initial
    case after5s
}

struct AIWaitingOverlay: View {
    let phase: WaitingPhase
    let primaryTitle: String
    let secondaryTitle: String
    let progressHint: String
    var waitingSeconds: Int? = nil
    let onKeepWaiting: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text(primaryTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(secondaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text(progressHint)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                if phase == .after5s {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button(action: onKeepWaiting) {
                                Text("待つ")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            Button(action: onLater) {
                                Text("あとで確認")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                        Button(action: {
                            PaywallCoordinator.shared.present()
                        }) {
                            Text("今すぐ結果を見る（プレミアム）")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
            }
            .padding(32)
        }
    }
}

// MARK: - Shared

private struct LoadingOverlay: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView()
            }
        }
    }
}
