//
//  RiskBadge.swift
//  GokigenNote
//
//  履歴カード用 Risk バッジ。
//

import SwiftUI

struct RiskBadge: View {
    let risk: LineRisk

    var body: some View {
        Text(risk.rawValue)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
