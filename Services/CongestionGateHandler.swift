//
//  CongestionGateHandler.swift
//  GokigenNote
//
//  resource-exhausted を検知し、CongestionGatePresenter で混雑モーダルを1枚表示する共通入口。
//

import Combine
import Foundation

enum CongestionOp {
    case lineStopper
    case reformulate
    case empathy
}

enum CongestionGateHandler {

    /// resource-exhausted をパースし、CongestionGatePresenter で表示。tier/retryAfterSeconds は details から。
    @MainActor
    static func presentIfNeeded(
        error: Error,
        op: CongestionOp,
        payloadKey: String
    ) -> Bool {
        let retryOp: RetryOp = switch op {
        case .lineStopper: .lineStopper
        case .reformulate: .reformulate
        case .empathy: .empathy
        }
        return presentCongestionGateIfNeeded(error: error, op: retryOp)
    }
}
