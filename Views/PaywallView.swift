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
                if pm.products.isEmpty {
                    await pm.loadProducts()
                }
                await pm.refreshEntitlements()
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
                Text("現在: \(planText(pm.plan))")
                Spacer()
                Text("AI枠: \(pm.remainingRewriteQuotaText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("言い換え・共感生成 無制限", systemImage: "infinity")
            Label("テンプレ保存（今後）", systemImage: "bookmark")
            Label("シチュエーション別（今後）", systemImage: "person.2")
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var productButtons: some View {
        VStack(spacing: 12) {
            if let monthly = pm.products.first(where: { $0.id == ProductID.premiumMonthly }) {
                Button {
                    Task { await pm.purchase(monthly) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("プレミアム（月額）").fontWeight(.semibold)
                            Text(priceText(monthly)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let lifetime = pm.products.first(where: { $0.id == ProductID.lifetime }) {
                Button {
                    Task { await pm.purchase(lifetime) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("買い切り").fontWeight(.semibold)
                            Text(priceText(lifetime)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
        VStack(spacing: 6) {
            Text("※購入はいつでもキャンセル/管理できます（App Storeのサブスクリプション）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func planText(_ plan: Plan) -> String {
        switch plan {
        case .free: return "無料"
        case .premium: return "プレミアム"
        case .lifetime: return "買い切り"
        }
    }

    private func priceText(_ product: Product) -> String {
        product.displayPrice
    }
}
