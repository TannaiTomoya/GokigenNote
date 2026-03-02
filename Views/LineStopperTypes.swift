//
//  LineStopperTypes.swift
//  GokigenNote
//

import Foundation

/// 待機UIとポーリングを同期させるための進捗（Service が保持）
enum LineStopperProgress: Equatable {
    case idle
    case waiting(seconds: Int)
    case processing
    case done
}

enum LineStopperRisk: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    static func < (lhs: LineStopperRisk, rhs: LineStopperRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "🟢"
        case .medium: return "🟠"
        case .high: return "🔴"
        }
    }

    var oneLiner: String {
        switch self {
        case .low: return "このまま送っても大崩れしにくい。"
        case .medium: return "刺さり方が強い。少し丸めると安全。"
        case .high: return "あとで後悔しやすい。送信前に止めよう。"
        }
    }
}

struct LineStopperSuggestion: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let text: String
}
