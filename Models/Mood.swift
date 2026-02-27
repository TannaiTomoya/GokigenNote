//
//  Untitled.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation
enum Mood: Int, Codable, CaseIterable, Identifiable {
    case veryHappy = 2
    case happy     = 1
    case neutral   = 0
    case sad       = -1
    case verySad   = -2
    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryHappy: return "😊"
        case .happy:     return "🙂"
        case .neutral:   return "😐"
        case .sad:       return "😞"
        case .verySad:   return "😢"
        }
    }

    var label: String {
        switch self {
        case .veryHappy: return "とても良い"
        case .happy:     return "良い"
        case .neutral:   return "ふつう"
        case .sad:       return "少しつらい"
        case .verySad:   return "つらい"
        }
    }
}
