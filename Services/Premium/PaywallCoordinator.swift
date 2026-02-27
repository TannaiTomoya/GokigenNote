//
//  PaywallCoordinator.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2026/02/27.
//
import Foundation
import Combine
@MainActor
final class PaywallCoordinator: ObservableObject {
    static let shared = PaywallCoordinator()

    @Published var isPresented: Bool = false

    private init() {}

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
