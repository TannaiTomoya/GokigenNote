//
//  PaywallCoordinator.swift
//  GokigenNote
//
//  アプリ全体で1つの Paywall sheet を制御。多重 present を抑止し、Root で .sheet を1箇所だけ持つ。
//  混雑ゲート（CongestionGate）も同一 sheet で modalKind により出し分け。
//

import Foundation
import Combine
import SwiftUI

enum PaywallPreselect: Equatable {
    case yearly
    case monthly
    case lifetime
}

enum ModalKind: Equatable {
    case paywall(preselect: PaywallPreselect?)
    case congestion(tier: QueueTier, retryAfterSeconds: Int?, retryAction: CongestionRetryAction?)
}

final class PaywallCoordinator: ObservableObject {
    static let shared = PaywallCoordinator()

    @Published private(set) var isPresented: Bool = false
    @Published var modalKind: ModalKind = .paywall(preselect: nil)

    var preselect: PaywallPreselect? {
        if case .paywall(let p) = modalKind { return p }
        return nil
    }

    @Published private(set) var presentCount: Int = 0   // デバッグ用（あとで消してOK）
    /// 無料10回使い切ったときの専用シート（「そのLINE…」「今はやめる/続きを見る」）
    @Published private(set) var isQuotaExceededSheetPresented: Bool = false
    /// HIGH判定時のアップセル（安全ベース文言・BottomSheet）
    @Published private(set) var isHighUpsellSheetPresented: Bool = false

    private var lastPresentedAt: Date = .distantPast

    private init() {}

    /// どこから呼ばれても安全に “一回だけ” 出す。年額誘導時は preselect: .yearly
    @MainActor
    func present(preselect: PaywallPreselect? = nil, throttleSeconds: TimeInterval = 0.8) {
        if isPresented { return }
        let now = Date()
        if now.timeIntervalSince(lastPresentedAt) < throttleSeconds { return }
        lastPresentedAt = now
        modalKind = .paywall(preselect: preselect)
        isPresented = true
        presentCount += 1
    }

    /// 混雑ゲート（resource-exhausted）。retryAfterSeconds でカウントダウン、retryAction で RetryBus に渡す種別。
    @MainActor
    func presentCongestion(
        tier: QueueTier,
        retryAfterSeconds: Int? = nil,
        retryAction: CongestionRetryAction? = nil,
        throttleSeconds: TimeInterval = 0.8
    ) {
        if isPresented { return }
        let now = Date()
        if now.timeIntervalSince(lastPresentedAt) < throttleSeconds { return }
        lastPresentedAt = now
        modalKind = .congestion(tier: tier, retryAfterSeconds: retryAfterSeconds, retryAction: retryAction)
        isPresented = true
    }

    @MainActor
    func dismiss() {
        isPresented = false
        modalKind = .paywall(preselect: nil)
    }

    /// 無料10回使い切ったときの専用シートを表示
    @MainActor
    func presentQuotaExceeded() {
        isQuotaExceededSheetPresented = true
    }

    @MainActor
    func dismissQuotaExceeded() {
        isQuotaExceededSheetPresented = false
    }

    @MainActor
    func presentHighUpsell() {
        isHighUpsellSheetPresented = true
    }

    @MainActor
    func dismissHighUpsell() {
        isHighUpsellSheetPresented = false
    }
}
