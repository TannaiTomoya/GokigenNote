//
//  HighResultView.swift
//  GokigenNote
//
//  判定別UI。HIGH=恐怖/守る、MEDIUM=不安/安定、LOW=向上/良くする。課金導線の温度差を守る。
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 判定ごとの課金導線の温度。HIGH=強め、MEDIUM=やわらかめ、LOW=ポジティブ
enum LineStopperUpsellType {
    case high   // 恐怖 → 守る
    case medium // 不安 → 安定させる
    case low    // 向上 → 良くする
}

// MARK: - High Result View

struct HighResultView: View {
    @ObservedObject var vm: LineStopperViewModel
    let inputText: String
    let onSaveDraft: (String) -> Void
    @State private var showReason = false
    @State private var showCopyToast = false
    @ObservedObject private var pm = PremiumManager.shared

    private var recommendedSuggestion: LineStopperSuggestion? {
        vm.selectedSuggestion ?? vm.suggestions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            alertBar
            recommendedCard
            otherSuggestionsSection
            sendLaterSection
            if !pm.effectivePlan.isPremium {
                UpsellCard(type: .high, onTap: {
                    PaywallCoordinator.shared.presentHighUpsell()
                })
            } else {
                PremiumExtrasView()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            if showCopyToast {
                Text("コピーしました")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyToast)
    }

    // 上部：危険アラートバー
    private var alertBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("送信は一旦ストップ")
                        .font(.subheadline.weight(.bold))
                    Text("この文面は誤解・衝突になりやすいです")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("このまま送ると、関係が悪くなる可能性があります")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $showReason) {
                Text(vm.riskOneLiner ?? "あとで後悔しやすい文面です。送信前に止めよう。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } label: {
                Text("理由を見る")
                    .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    // 1タップ救済：おすすめ（安全）カード
    private var recommendedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("おすすめ（安全）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let s = recommendedSuggestion {
                Text(s.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                copyRecommended()
            } label: {
                Label("コピーしてLINEへ", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedProminentButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // 他の案（3つ）
    private var otherSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("他の案")
                .font(.subheadline.weight(.semibold))
            ForEach(vm.suggestions) { s in
                Button {
                    vm.selectedSuggestion = s
                } label: {
                    HStack {
                        Text(s.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if vm.selectedSuggestion?.id == s.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    vm.selectedSuggestion?.id == s.id ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
        }
    }

    // 送らない
    private var sendLaterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onSaveDraft(inputText)
            } label: {
                Label("今は送らない（下書きに保存）", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
        }
    }

    private func copyRecommended() {
        guard let s = recommendedSuggestion else { return }
        #if os(iOS)
        UIPasteboard.general.string = s.text
        #endif
        if let idx = vm.suggestions.firstIndex(where: { $0.id == s.id }) {
            vm.recordCopy(label: s.label, index: idx)
        }
        showCopyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyToast = false
        }
    }
}

// MARK: - Upsell Card（判定別コピー：HIGH=強め / MEDIUM=やわらかめ / LOW=ポジティブ）

struct UpsellCard: View {
    let type: LineStopperUpsellType
    let onTap: () -> Void

    private var title: String {
        switch type {
        case .high: return "もっと安全に整える"
        case .medium: return "後悔しない形に整えませんか？"
        case .low: return "ただ、あなたの傾向的に少しだけ損しています。"
        }
    }

    private var bullets: [String] {
        switch type {
        case .high:
            return ["別パターンの改善案を追加", "「なぜ危険か」を具体的に解説", "混雑時もすぐ使える"]
        case .medium:
            return ["トゲ抜きバージョン", "感情を消すバージョン", "大人対応バージョン"]
        case .low:
            return ["相手に好印象を残す言い回し", "「距離を縮める」バージョン", "「大人っぽく整える」バージョン"]
        }
    }

    private var buttonTitle: String {
        switch type {
        case .high: return "さらに整える（プレミアム）"
        case .medium: return "後悔しない形に整える（プレミアム）"
        case .low: return "あなた専用の改善を見る（プレミアム）"
        }
    }

    private var isCompact: Bool { type == .low }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            Text(title)
                .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.bold))
            if !isCompact {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { b in
                        Text("・\(b)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if isCompact {
                Button(action: onTap) {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
            } else {
                Button(action: onTap) {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding(isCompact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 履歴アップセル（LTV：未来の自分のために課金）

struct HistoryUpsellCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("この改善、あとで見返せます")
                        .font(.caption.weight(.medium))
                    Text("＋履歴に保存（プレミアム）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill).opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Premium Extras（有料ユーザー向け・プレースホルダー）

struct PremiumExtrasView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プレミアム")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("追加の改善案・理由の詳細・優先処理をご利用中です。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - LOW Result（安心・質の向上型。危険路線はやらない）

struct LowResultView: View {
    @ObservedObject var vm: LineStopperViewModel
    @State private var showCopyToast = false
    @ObservedObject private var pm = PremiumManager.shared

    private var recommendedSuggestion: LineStopperSuggestion? {
        vm.selectedSuggestion ?? vm.suggestions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            safeMessageBar
            recommendedBlock
            otherSuggestionsSection
            copyAndClearRow
            if !pm.effectivePlan.isPremium {
                UpsellCard(type: .low, onTap: {
                    PaywallCoordinator.shared.present()
                })
                HistoryUpsellCard(onTap: { PaywallCoordinator.shared.present() })
            } else {
                PremiumExtrasView()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            if showCopyToast {
                Text("コピーしました")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyToast)
    }

    private var safeMessageBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("この文章でも問題ありません。")
                    .font(.subheadline.weight(.semibold))
                Text("ただ、あなたの傾向的に少しだけ損しています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recommendedBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("おすすめの案：")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let s = recommendedSuggestion {
                Text(s.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var otherSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("他の案")
                .font(.subheadline.weight(.semibold))
            ForEach(vm.suggestions) { s in
                Button {
                    vm.selectedSuggestion = s
                } label: {
                    HStack {
                        Text(s.label).font(.subheadline)
                        Spacer()
                        if vm.selectedSuggestion?.id == s.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    vm.selectedSuggestion?.id == s.id ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
        }
    }

    private var copyAndClearRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    guard let s = recommendedSuggestion else { return }
                    #if os(iOS)
                    UIPasteboard.general.string = s.text
                    #endif
                    if let idx = vm.suggestions.firstIndex(where: { $0.id == s.id }) {
                        vm.recordCopy(label: s.label, index: idx)
                    }
                    showCopyToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyToast = false }
                } label: {
                    Text("コピーする")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())

                Button {
                    vm.resetResult()
                    vm.inputText = ""
                } label: {
                    Text("クリア")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
            }
            Button {
                Task { await vm.generate() }
            } label: {
                Text("もう一度チェック")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
        }
    }
}

// MARK: - MEDIUM Result（ちょっと不安・安心を買う）

struct MediumResultView: View {
    @ObservedObject var vm: LineStopperViewModel
    @State private var showCopyToast = false
    @ObservedObject private var pm = PremiumManager.shared

    private var recommendedSuggestion: LineStopperSuggestion? {
        vm.selectedSuggestion ?? vm.suggestions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cautionMessageBar
            suggestionPicker
            copyAndClearRow
            if !pm.effectivePlan.isPremium {
                UpsellCard(type: .medium, onTap: {
                    PaywallCoordinator.shared.present()
                })
                HistoryUpsellCard(onTap: { PaywallCoordinator.shared.present() })
            } else {
                PremiumExtrasView()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            if showCopyToast {
                Text("コピーしました")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyToast)
    }

    private var cautionMessageBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("やや注意が必要です。")
                    .font(.subheadline.weight(.semibold))
                Text("少し強く伝わる可能性があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("このまま送る人：62%　後悔した人：38%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var suggestionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("改善案（3つ）")
                .font(.subheadline.weight(.semibold))
            ForEach(vm.suggestions) { s in
                Button {
                    vm.selectedSuggestion = s
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.label).font(.subheadline.weight(.medium))
                            Spacer()
                            if vm.selectedSuggestion?.id == s.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        Text(s.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var copyAndClearRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    guard let s = recommendedSuggestion else { return }
                    #if os(iOS)
                    UIPasteboard.general.string = s.text
                    #endif
                    if let idx = vm.suggestions.firstIndex(where: { $0.id == s.id }) {
                        vm.recordCopy(label: s.label, index: idx)
                    }
                    showCopyToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyToast = false }
                } label: {
                    Text("コピーする")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())

                Button {
                    vm.resetResult()
                    vm.inputText = ""
                } label: {
                    Text("クリア")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
            }
            Button {
                Task { await vm.generate() }
            } label: {
                Text("もう一度チェック")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
        }
    }
}

// MARK: - HIGH専用アップセルシート（安全ベース・BottomSheet）

struct HighUpsellSheet: View {
    private let coordinator = PaywallCoordinator.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("今のままでも送れますが、もう少し整えると誤解を避けやすくなります。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        coordinator.dismissHighUpsell()
                        coordinator.present()
                    } label: {
                        Text("年額で優先的にチェックする")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())

                    Button {
                        coordinator.dismissHighUpsell()
                        coordinator.present()
                    } label: {
                        Text("月額で始める")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())

                    Button {
                        coordinator.dismissHighUpsell()
                    } label: {
                        Text("今回はやめる")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("もう一段、整えますか？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        coordinator.dismissHighUpsell()
                    }
                }
            }
        }
    }
}
