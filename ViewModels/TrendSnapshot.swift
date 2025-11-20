// TrendSnapshot.swift
// GokigenNote

import Foundation

struct TrendSnapshot {
    let averageScore: Double
    let positiveRatio: Double
    let negativeRatio: Double
    let consecutiveDays: Int
    let sampleCount: Int
    let lastUpdated: Date
    let dominantEmoji: String
    let feedback: String

    // データがまだないとき用の初期値
    static let empty = TrendSnapshot(
        averageScore: 0,
        positiveRatio: 0,
        negativeRatio: 0,
        consecutiveDays: 0,
        sampleCount: 0,
        lastUpdated: .distantPast,
        dominantEmoji: "🙂",
        feedback: "まだデータが少ないよ。1日の終わりに一言だけ書いてみよう。"
    )
}
