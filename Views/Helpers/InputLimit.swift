//
//  InputLimit.swift
//  GokigenNote
//
//  入力文字数上限（コスト最適化）。サーバーでも強制トリムするが、クライアントでも最小限に制限する。
//

import Foundation

enum InputLimit {
    /// 無料 400 / 有料 800（言い換え・危険度共通）
    static func maxCharsReformulate(isPremium: Bool) -> Int { isPremium ? 800 : 400 }
    static func maxCharsLineStopper(isPremium: Bool) -> Int { isPremium ? 800 : 400 }

    static let lineStopper = 600
    static let reformulate = 400
    static let empathy = 800

    /// 指定文字数で切り詰め（サーバー送信前に必ず適用）
    static func clampText(_ s: String, maxChars: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx])
    }
}

