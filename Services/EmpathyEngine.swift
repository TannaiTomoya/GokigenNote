//
//  EmpathyEngine.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation

enum EmpathyEngine {
    // 簡易なネガティブ判定用キーワード
    static let negativeKeywords = [
        "つかれ", "疲れ", "しんど", "ムカ", "不安", "かなしい", "悲し",
        "こわ", "怖", "きつ", "イライラ", "怒", "失敗"
    ]

    /// 入力文＋気分から、"やさしい言い換え" と "次の一歩" を返す（ルールベース）
    static func rewrite(original: String, mood: Mood) -> (empathy: String, nextStep: String) {
        let lower = original.lowercased()
        let isNegative = mood.rawValue < 0 || negativeKeywords.contains { lower.contains($0) }

        if isNegative {
            let empathy = "しんどい中でも、ここまで来られたね。まずは深呼吸。あなたは悪くないよ。"
            let next    = "今日はゆっくり休もう。できれば温かい飲み物を一杯。"
            return (empathy, next)
        } else if mood.rawValue > 0 {
            let empathy = "うまくいったね。その感覚はあなたの力だよ。"
            let next    = "小さくてもOK。もう一つ『やってみたいこと』を書いてみよう。"
            return (empathy, next)
        } else {
            let empathy = "淡々と過ごせたこと自体、十分えらい。"
            let next    = "体をほぐすストレッチを1分だけ。気分が少し軽くなるよ。"
            return (empathy, next)
        }
    }
}
