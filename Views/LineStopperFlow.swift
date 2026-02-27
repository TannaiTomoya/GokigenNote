//
//  LineStopperFlow.swift
//  GokigenNote
//
//  Drop-in flow: Input → Result → Copy → (optional) Paywall
//

import SwiftUI

// MARK: - Models

enum LineStopperRisk: Int, Comparable {
    case low = 0, medium = 1, high = 2
    static func < (lhs: LineStopperRisk, rhs: LineStopperRisk) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "🟢"
        case .medium: return "🟠"
        case .high: return "🔴"
        }
    }

    var oneLiner: String {
        switch self {
        case .low: return "このまま送っても大崩れしにくい。"
        case .medium: return "刺さり方が強い。少し丸めると安全。"
        case .high: return "あとで後悔しやすい。送信前に止めよう。"
        }
    }
}

struct LineStopperSuggestion: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let text: String
}

// MARK: - ViewModel

@MainActor
final class LineStopperViewModel: ObservableObject {
    nonisolated init() {}

    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var risk: LineStopperRisk?
    @Published var riskOneLiner: String?
    @Published var suggestions: [LineStopperSuggestion] = []
    @Published var selectedSuggestion: LineStopperSuggestion?

    @Published var shouldShowPaywall: Bool = false

    func resetResult() {
        risk = nil
        riskOneLiner = nil
        suggestions = []
        selectedSuggestion = nil
        errorMessage = nil
    }

    func generate() async {
        errorMessage = nil
        shouldShowPaywall = false

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "LINE文を貼り付けてください。"
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1) QuotaService でサーバ側ゲート
        let quotaResult: QuotaCheckResult
        do {
            quotaResult = try await QuotaService.shared.consumeRewrite(op: .reformulate, draftEntryId: nil)
        } catch {
            if QuotaService.isUnauthenticated(error) {
                errorMessage = "ログインが必要です。"
            } else {
                errorMessage = error.localizedDescription
            }
            return
        }

        if !quotaResult.allowed {
            shouldShowPaywall = true
            if quotaResult.paywall {
                PaywallCoordinator.shared.present()
            }
            return
        }

        // 2) Gemini で危険度 + 改善案3つ取得
        do {
            let (riskRaw, oneLiner, suggestionTuples) = try await GeminiService.shared.generateLineStopperResult(text: trimmed)

            let mappedRisk: LineStopperRisk
            switch riskRaw.uppercased() {
            case "HIGH": mappedRisk = .high
            case "MEDIUM": mappedRisk = .medium
            default: mappedRisk = .low
            }
            risk = mappedRisk
            riskOneLiner = oneLiner.isEmpty ? nil : oneLiner
            suggestions = suggestionTuples.map { LineStopperSuggestion(label: $0.label, text: $0.text) }
            selectedSuggestion = suggestions.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copySelected() {
        guard let text = selectedSuggestion?.text else { return }
        UIPasteboard.general.string = text
    }
}

// MARK: - Root

struct LineStopperRootView: View {
    @StateObject private var vm = LineStopperViewModel()
    @ObservedObject private var pm = PremiumManager.shared

    var body: some View {
        NavigationStack {
            LineStopperInputView(vm: vm)
                .navigationTitle("地雷LINEストッパー")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $vm.shouldShowPaywall) {
                    PaywallView()
                }
                .overlay { LoadingOverlay(isLoading: vm.isLoading || pm.isLoading) }
        }
    }
}

// MARK: - Input Screen

struct LineStopperInputView: View {
    @ObservedObject var vm: LineStopperViewModel

    var body: some View {
        VStack(spacing: 16) {
            header

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

            if let err = vm.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await vm.generate() }
            } label: {
                Text("危険度をチェックする")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            quotaRow

            Divider().padding(.top, 4)

            if vm.risk != nil {
                LineStopperResultView(vm: vm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 8)
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: vm.risk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("そのLINE、あとで後悔するよ")
                .font(.title3.weight(.bold))
            Text("送信前に一回だけ止める。危険度と“安全な一言”に変換します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quotaRow: some View {
        HStack {
            Text("現在: \(PremiumManager.shared.effectivePlan.displayName)")
            Spacer()
            Text("AI枠: \(PremiumManager.shared.remainingRewriteQuotaText)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
