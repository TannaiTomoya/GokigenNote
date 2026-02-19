//
//  PaywallCoordinator.swift
//  GokigenNote
//
//  アプリ全体で1つの Paywall sheet を制御。多重 present を抑止し、Root で .sheet を1箇所だけ持つ。
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class PaywallCoordinator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    static let shared = PaywallCoordinator()

    @Published private(set) var isPresented: Bool = false
    @Published private(set) var presentCount: Int = 0   // デバッグ用（あとで消してOK）

    private var lastPresentedAt: Date = .distantPast

    private init() {}

    /// どこから呼ばれても安全に “一回だけ” 出す
    func present(throttleSeconds: TimeInterval = 0.8) {
        if isPresented { return }

        let now = Date()
        if now.timeIntervalSince(lastPresentedAt) < throttleSeconds { return }

        lastPresentedAt = now
        objectWillChange.send()
        isPresented = true
        presentCount += 1
    }

    func dismiss() {
        objectWillChange.send()
        isPresented = false
    }
}
