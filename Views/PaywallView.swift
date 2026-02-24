//
//  PaywallView.swift
//  GokigenNote
//
//  StoreKit2 購入/復元まで含む Paywall。sheet または設定から表示。
//

import SwiftUI
import StoreKit

private enum LegalSheet: Identifiable {
    case terms, privacy
    var id: Int { switch self { case .terms: return 1; case .privacy: return 2 } }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pm = PremiumManager.shared
    @State private var legalSheet: LegalSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                featureList

                PaywallProductButtons(pm: pm, orderedProducts: orderedProducts, featuredProductID: featuredProductID)

                footer
            }
            .padding()
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
            .overlay {
                LoadingOverlay(isLoading: pm.isLoading)
            }
            .onAppear {
                Task {
                    if pm.availableProducts.isEmpty {
                        await pm.loadProducts()
                    }
                    await pm.refreshEntitlements(mode: .startupCautious)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プレミアムでできること")
                .font(.title2.weight(.bold))

            Text("言い換え・例文・共感の生成が無制限（サブスク）／買い切りは月200回まで。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("無料プラン：1日10回まで")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("現在: \(planText(pm.effectivePlan))")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AI枠: \(pm.remainingRewriteQuotaText)")
                    if !pm.entitlementsLoaded {
                        Text("状態確認中…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("・言い換え無制限（サブスク）／月200回（買い切り）")
            Text("・共感生成無制限（サブスク）／月200回（買い切り）")
            Text("・思考整理を加速")
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
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

    /// 表示順：ProductID.sortKey で並べ替え（存在するものだけ、追加時も漏れない）
    private var orderedProducts: [Product] {
        pm.availableProducts.sorted {
            ProductID.sortKey(for: $0.id) < ProductID.sortKey(for: $1.id)
        }
    }

    /// 推し商品（存在する中で優先：年額 → 月額 → 買い切り）。該当なしなら nil
    private var featuredProductID: String? {
        let ids = Set(pm.availableProducts.map(\.id))
        if ids.contains(ProductID.premiumYearly) { return ProductID.premiumYearly }
        if ids.contains(ProductID.premiumMonthly) { return ProductID.premiumMonthly }
        if ids.contains(ProductID.lifetime) { return ProductID.lifetime }
        return nil
    }
}

// MARK: - overlay 型合成軽量化
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

// MARK: - 型推論軽量化のため別 View に分割
private struct PaywallProductButtons: View {
    @ObservedObject var pm: PremiumManager
    let orderedProducts: [Product]
    let featuredProductID: String?

    private func buy(_ product: Product) {
        Task { await pm.purchase(product) }
    }

    private func doRestore() {
        Task { await pm.restore() }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(orderedProducts, id: \.id) { product in
                Button {
                    buy(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ProductID.displayName(for: product.id)).fontWeight(.semibold)
                            Text(product.displayPrice).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(product.id == featuredProductID ? BorderedProminentButtonStyle() : BorderedButtonStyle())
            }

            if orderedProducts.isEmpty {
                Text("商品を取得できませんでした。通信状況やストア設定、サンドボックスでのサインインを確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }

            Text("価格は各プランに表示のとおり（月額・年額・買い切り）")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("購入を復元") {
                doRestore()
            }
            .font(.subheadline)
            .padding(.top, 4)

            if let err = pm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
