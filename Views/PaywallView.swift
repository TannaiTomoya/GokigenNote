//
//  PaywallView.swift
//  GokigenNote
//
//  StoreKit2 購入/復元まで含む Paywall。sheet または設定から表示。
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pm = PremiumManager.shared
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                featureList

                productButtons

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
                if pm.isLoading {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView()
                    }
                }
            }
            .task {
                if pm.availableProducts.isEmpty {
                    await pm.loadProducts()
                }
                await pm.refreshEntitlements(mode: .startupCautious)
            }
            .sheet(isPresented: $showTerms) {
                TermsOfServiceView()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("言い換え・共感生成を無制限に")
                .font(.title2.weight(.bold))

            Text("無料枠は「言い換え / 共感生成」で同じ回数枠を消費します。")
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
            Text("・言い換え無制限")
            Text("・共感生成無制限")
            Text("・思考整理を加速")
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var productButtons: some View {
        VStack(spacing: 12) {
            ForEach(orderedProducts, id: \.id) { product in
                Button {
                    Task { await pm.purchase(product) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ProductID.displayName(for: product.id)).fontWeight(.semibold)
                            Text(priceText(product)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(product.id == featuredProductID ? .borderedProminent : .bordered)
            }

            if orderedProducts.isEmpty {
                Text("商品を取得できませんでした。通信状況やストア設定、サンドボックスでのサインインを確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }

            Button("購入を復元") {
                Task { await pm.restore() }
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

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button("利用規約") { showTerms = true }
                    .font(.caption)
                Button("プライバシーポリシー") { showPrivacy = true }
                    .font(.caption)
            }
            Text("※購入はいつでもキャンセル/管理できます（App Storeのサブスクリプション）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func planText(_ plan: Plan) -> String {
        plan.displayName
    }

    private func priceText(_ product: Product) -> String {
        product.displayPrice
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
