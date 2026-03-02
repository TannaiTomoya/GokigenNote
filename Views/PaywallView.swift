//
//  PaywallView.swift
//  GokigenNote
//
//  StoreKit2 購入/復元まで含む Paywall。sheet または設定から表示。
//  参考: 課金特典チェックリスト・プラン選択・サブスク管理（審査対応）
//

import SwiftUI
import StoreKit
import UIKit

private enum LegalSheet: Identifiable {
    case terms, privacy
    var id: Int { switch self { case .terms: return 1; case .privacy: return 2 } }
}

// MARK: - 課金特典（緑チェックの箇条書き）
private struct BenefitRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pm = PremiumManager.shared
    @ObservedObject private var coordinator = PaywallCoordinator.shared
    @State private var legalSheet: LegalSheet?
    /// プラン選択（ラジオ風）。購入はこの選択で実行
    @State private var selectedProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    currentPlanCard
                    benefitsCard
                    planSelectionSection
                    primaryActionSection
                    legalFooter
                }
                .padding()
            }
            .navigationTitle("プレミアム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        PaywallCoordinator.shared.dismiss()
                        dismiss()
                    }
                }
            }
            .overlay { LoadingOverlay(isLoading: pm.isLoading) }
            .onAppear {
                Task {
                    if pm.availableProducts.isEmpty {
                        await pm.loadProducts()
                    }
                    await pm.refreshEntitlements(mode: .startupCautious)
                }
                if selectedProductID == nil {
                    selectedProductID = featuredProductID ?? orderedProducts.first?.id
                }
            }
            .sheet(item: $legalSheet) { sheet in
                switch sheet {
                case .terms: TermsOfServiceView()
                case .privacy: PrivacyPolicyView()
                }
            }
        }
    }

    /// 現在のプラン状況（参考画像の上部カード）
    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GokigenNote プレミアム")
                .font(.subheadline.weight(.semibold))
            if pm.effectivePlan.isPremium {
                Text("現在: \(planText(pm.effectivePlan))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if pm.effectivePlan.isYearly {
                    Text("待機なし（即結果）・優先処理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("現在、プレミアムに加入していません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Text("AI枠: \(pm.remainingRewriteQuotaText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 課金特典（白カード＋緑チェックリスト）
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("課金特典")
                .font(.headline)
            BenefitRow(text: "言い換え・例文・共感の生成が無制限（サブスク）／買い切りは月200回まで")
            BenefitRow(text: "優先キュー（混雑時も高速）")
            BenefitRow(text: "履歴の傾向分析")
            BenefitRow(text: "回数上限に余裕")
            BenefitRow(text: "年額プラン：待機なし（即結果）・優先処理")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    /// プランを選択（ラジオ風・価格表示）
    private var planSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プランを選択")
                .font(.headline)
            ForEach(orderedProducts, id: \.id) { product in
                planRow(product: product)
            }
            if orderedProducts.isEmpty {
                VStack(spacing: 8) {
                    Text("商品を取得できませんでした")
                        .font(.subheadline.weight(.medium))
                    Text("通信状況をご確認のうえ、再度お試しください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
    }

    private func planRow(product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductID.displayName(for: product.id))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(product.displayPrice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// 購入を続ける ＋ サブスク管理 ＋ 復元
    private var primaryActionSection: some View {
        VStack(spacing: 12) {
            if let product = orderedProducts.first(where: { $0.id == selectedProductID }) {
                Button {
                    Task { await pm.purchase(product) }
                } label: {
                    HStack {
                        Text(purchaseButtonTitle(for: product))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }

            Button {
                openManageSubscriptions()
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("サブスクリプションを管理")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(BorderedButtonStyle())

            Button("購入を復元") {
                Task { await pm.restore() }
            }
            .font(.subheadline)

            Text("価格は各プランに表示のとおり（月額・年額・買い切り）")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func openManageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                // シート非対応環境などは無視（審査用ボタンは表示済み）
            }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button("利用規約") { legalSheet = .terms }
                    .font(.caption)
                Button("プライバシーポリシー") { legalSheet = .privacy }
                    .font(.caption)
            }
            Text("自動更新：サブスクは自動更新され、更新の24時間前に課金されます。解約は設定＞サブスクリプションからいつでも可能です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func planText(_ plan: Plan) -> String {
        plan.displayName
    }

    private func purchaseButtonTitle(for product: Product) -> String {
        let name = ProductID.displayName(for: product.id)
        if product.id == ProductID.lifetime {
            return "\(name)を購入"
        }
        return "\(name)を始める"
    }

    private var orderedProducts: [Product] {
        pm.availableProducts.sorted {
            ProductID.sortKey(for: $0.id) < ProductID.sortKey(for: $1.id)
        }
    }

    private var featuredProductID: String? {
        let ids = Set(pm.availableProducts.map(\.id))
        if coordinator.preselect == .yearly, ids.contains(ProductID.premiumYearly) { return ProductID.premiumYearly }
        if coordinator.preselect == .monthly, ids.contains(ProductID.premiumMonthly) { return ProductID.premiumMonthly }
        if coordinator.preselect == .lifetime, ids.contains(ProductID.lifetime) { return ProductID.lifetime }
        if ids.contains(ProductID.premiumYearly) { return ProductID.premiumYearly }
        if ids.contains(ProductID.premiumMonthly) { return ProductID.premiumMonthly }
        if ids.contains(ProductID.lifetime) { return ProductID.lifetime }
        return nil
    }
}

// MARK: - overlay
private struct LoadingOverlay: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView()
            }
        }
    }
}
