//  TrendSnapshot.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//

import Foundation

struct TrendSnapshot: Equatable {
    let averageScore: Double
    let positiveRatio: Double
    let negativeRatio: Double
    let consecutiveDays: Int
    let sampleCount: Int
    let lastUpdated: Date
    let dominantEmoji: String
    let feedback: String

    var isEmpty: Bool { sampleCount == 0 }

    static let empty = TrendSnapshot(
        averageScore: 0,
        positiveRatio: 0,
        negativeRatio: 0,
        consecutiveDays: 0,
        sampleCount: 0,
        lastUpdated: .distantPast,
        dominantEmoji: "🙂",
        feedback: "まだ記録がありません。今日の一言から始めてみましょう。"
    )
}
