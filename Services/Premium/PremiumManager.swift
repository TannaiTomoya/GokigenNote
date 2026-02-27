//
//  PremiumManager.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2026/02/27.
import Foundation
import StoreKit
import FirebaseAuth
import Combine
// GokigenNoteApp.swift の .refreshEntitlements(mode: .startupCautious) に必要
enum PremiumRefreshMode {
    case startupCautious
    case userInitiated
}

@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var lastErrorMessage: String? = nil

    private init() {}

    func start() {
        // 最小：起動時に一度だけリフレッシュしておく
        Task { await refreshEntitlements(mode: .startupCautious) }
    }

    /// Auth確定タイミングで呼ばれる想定（あなたの修正方針に合わせて）
    func setCurrentUserId(_ uid: String?) {
        // ここでは「保持だけ」でもOK。必要になったら Firestore と紐づける。
        // ひとまず uid が取れたタイミングで entitlement を取り直す。
        Task { await refreshEntitlements(mode: .startupCautious) }
    }

    /// StoreKit 2 の現在の購入状態から premium 判定
    func refreshEntitlements(mode: PremiumRefreshMode) async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let tx):
                // auto-renewable / non-consumable を premium 扱いにする最小実装
                if tx.productType == .autoRenewable || tx.productType == .nonConsumable {
                    hasActive = true
                }
            case .unverified:
                continue
            }
        }
        self.isPremium = hasActive
        self.lastErrorMessage = nil
    }

    /// 「購入を復元」ボタン用（PaywallView から呼ぶ）
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements(mode: .userInitiated)
        } catch {
            self.lastErrorMessage = error.localizedDescription
        }
    }
}

