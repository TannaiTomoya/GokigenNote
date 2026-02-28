//
//  PromptProvider.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation

enum PromptProvider {
    static let prompts: [String] = [
        "今日は、何がいちばん楽しかった？",
        "今日は、何がいちばんつらかった？",
        "今日は、どんな気分だった？",
        "今の自分に一言かけるなら？",
        "小さな『できたこと』は？"
    ]

    static func random() -> String {
        prompts.randomElement() ?? "今日は、どんな気分だった？"
    }
}
