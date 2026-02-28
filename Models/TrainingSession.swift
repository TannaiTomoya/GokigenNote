//
//  TrainingSession.swift
//  GokigenNote
//

import Foundation

/// ワーキングメモリトレーニングのゲーム種類
enum GameType: String, Codable, CaseIterable, Identifiable {
    case numberMemory   = "numberMemory"
    case reverseMemory  = "reverseMemory"
    case nBack          = "nBack"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .numberMemory:  return "数字記憶"
        case .reverseMemory: return "逆順記憶"
        case .nBack:         return "n-backゲーム"
        }
    }

    var description: String {
        switch self {
        case .numberMemory:  return "表示された数字を覚えて入力"
        case .reverseMemory: return "数字を逆順で答える"
        case .nBack:         return "n個前と同じか判定"
        }
    }

    var icon: String {
        switch self {
        case .numberMemory:  return "number.circle.fill"
        case .reverseMemory: return "arrow.left.arrow.right.circle.fill"
        case .nBack:         return "brain.head.profile"
        }
    }
}

/// トレーニングセッション1回分の記録
struct TrainingSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var gameType: GameType
    var difficulty: Int
    var score: Int          // 正解率 0-100
    var correctCount: Int   // 正解数
    var totalCount: Int     // 出題数
}
