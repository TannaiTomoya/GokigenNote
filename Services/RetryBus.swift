//
//  RetryBus.swift
//  GokigenNote
//
//  混雑モーダル「再試行」を AsyncStream で届ける。
//

import Foundation

enum RetryOp: String, Sendable {
    case lineStopper
    case reformulate
    case empathy
}

struct RetryRequest: Sendable {
    let op: RetryOp
}

/// 既存の NotificationCenter 購読用（bridge が post する）
enum CongestionRetryAction: String, Equatable {
    case reformulate
    case lineStopper
    case empathy
}

actor RetryBus {
    static let shared = RetryBus()

    static let retryRequested = Notification.Name("RetryBus.retryRequested")

    private var continuation: AsyncStream<RetryRequest>.Continuation?

    func stream() -> AsyncStream<RetryRequest> {
        AsyncStream { cont in
            self.continuation = cont
        }
    }

    func send(_ req: RetryRequest) {
        continuation?.yield(req)
    }

    static func parseAction(_ notification: Notification) -> CongestionRetryAction? {
        guard let raw = notification.userInfo?["action"] as? String else { return nil }
        return CongestionRetryAction(rawValue: raw)
    }

    static func post(_ action: CongestionRetryAction) {
        NotificationCenter.default.post(
            name: retryRequested,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }
}
