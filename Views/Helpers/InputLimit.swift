//
//  InputLimit.swift
//  GokigenNote
//
//  入力文字数上限（コスト最適化）。サーバーでも強制トリムするが、クライアントでも最小限に制限する。
//

import Foundation

enum InputLimit {
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

