//
//  EmpathyEngine.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation
enum EmpathyEngine {
    static let negativeKeywords = [
        "つかれ", "疲れ", "しんど", "ムカ", "不安", "かなしい", "悲し",
        "こわ", "怖", "きつ", "イライラ", "怒", "失敗"
    ]

    static func rewrite(original: String, mood: Mood) -> (String, String) {
        let lower = original.lowercased()
        let isNegative = mood.rawValue < 0 || negativeKeywords.contains { lower.contains($0) }

        if isNegative {
            return (
                "しんどい中でも、ここまで来られたね。まずは深呼吸。あなたは悪くないよ。",
                "今日はゆっくり休もう。できれば温かい飲み物を一杯。"
            )
        } else if mood.rawValue > 0 {
            return (
                "うまくいったね。その感覚はあなたの力だよ。",
                "小さくてもOK。もう一つ『やってみたいこと』を書いてみよう。"
            )
        } else {
            return (
                "淡々と過ごせたこと自体、十分えらい。",
                "体をほぐすストレッチを1分だけ。気分が少し軽くなるよ。"
            )
        }
    }
}
