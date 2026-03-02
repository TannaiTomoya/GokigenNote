//
//  CongestionGatePresenter.swift
//  GokigenNote
//
//  resource-exhausted の details で混雑モーダルを1枚表示。tier/retryAfterSeconds は details から。
//

import Combine
import Foundation
import SwiftUI
import FirebaseFunctions

@MainActor
final class CongestionGatePresenter: ObservableObject {
    static let shared = CongestionGatePresenter()

    @Published var isPresented = false
    @Published var details: RateLimitDetails?
    @Published var retryRequest: RetryRequest?

    private var lastPresentedAt = Date.distantPast

    func present(details: RateLimitDetails, retryRequest: RetryRequest) {
        let now = Date()
        if now.timeIntervalSince(lastPresentedAt) < 0.8 { return }
        lastPresentedAt = now

        self.details = details
        self.retryRequest = retryRequest
        self.isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

/// 共通ハンドラ：resource-exhausted の details を拾って CongestionGatePresenter で表示
@MainActor
func presentCongestionGateIfNeeded(error: Error, op: RetryOp) -> Bool {
    let ns = error as NSError

    guard ns.domain == FunctionsErrorDomain,
          let code = FunctionsErrorCode(rawValue: ns.code),
          code == .resourceExhausted
    else { return false }

    let dict: [String: Any]? = (ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any])
        ?? (ns.userInfo["details"] as? [String: Any])
    guard let dict,
          let data = try? JSONSerialization.data(withJSONObject: dict),
          let details = try? JSONDecoder().decode(RateLimitDetails.self, from: data)
    else { return false }

    CongestionGatePresenter.shared.present(
        details: details,
        retryRequest: RetryRequest(op: op)
    )
    return true
}
