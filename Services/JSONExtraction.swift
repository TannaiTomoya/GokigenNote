//
//  JSONExtraction.swift
//  GokigenNote
//
//  Gemini 等が前後に説明文・コードフェンスを付けても復旧できる抽出・デコード
//

import Foundation

enum JSONExtractionError: Error {
    case noJSONObjectFound
}

/// 文字列から JSON らしい部分を抜き出して返す（失敗時は nil）。
/// - 最優先: <OUTPUT>...</OUTPUT> 内
/// - 次: ``` ... ``` のフェンスブロック
/// - それ以外: brace block を抽出
func extractJSON(from text: String) -> String? {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }

    // 0) OUTPUTタグ最優先
    if let output = extractTagBlock(from: raw, open: "<OUTPUT>", close: "</OUTPUT>") {
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brace = extractBraceBlock(from: body) { return brace }
        if body.contains("{") { return body }
    }

    // 1) fenced block 優先
    if let fenced = extractFirstFenceBlock(from: raw) {
        let body = stripLeadingJSONLanguageTag(fenced)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let brace = extractBraceBlock(from: body) {
            return brace
        }
        // brace が取れなくても { を含むなら body を返す（repair に回す）
        if body.contains("{") { return body }
    }

    // 2) no fence: brace block のみ
    return extractBraceBlock(from: raw)
}

private func extractTagBlock(from s: String, open: String, close: String) -> String? {
    guard let o = s.range(of: open) else { return nil }
    let rest = s[o.upperBound...]
    guard let c = rest.range(of: close) else { return nil }
    let content = String(rest[..<c.lowerBound])
    return content.isEmpty ? nil : content
}

private func extractFirstFenceBlock(from raw: String) -> String? {
    guard let open = raw.range(of: "```") else { return nil }
    let rest = raw[open.upperBound...]
    guard let close = rest.range(of: "```") else { return nil }
    let content = String(rest[..<close.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return content.isEmpty ? nil : content
}

/// 先頭行が "json" / "JSON" などなら剥がす
private func stripLeadingJSONLanguageTag(_ s: String) -> String {
    let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = lines.first else { return s }
    if first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "json" {
        return lines.dropFirst().joined(separator: "\n")
    }
    return s
}

/// 文字列を走査し、" と \ を考慮して「文字列の外」だけ { } を数える。
/// 最初に depth=1 になった地点から、depth が 0 に戻る地点までを返す。
private func extractBraceBlock(from s: String) -> String? {
    var inString = false
    var escaped = false
    var depth = 0
    var startIndex: String.Index?

    var i = s.startIndex
    while i < s.endIndex {
        let ch = s[i]

        if inString {
            if escaped {
                escaped = false
            } else {
                if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            }
        } else {
            if ch == "\"" {
                inString = true
            } else if ch == "{" {
                if depth == 0 { startIndex = i }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let block = String(s[start...i])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return block.isEmpty ? nil : block
                    }
                }
            }
        }

        i = s.index(after: i)
    }

    // 閉じ } が足りない等：repair に任せる。ここでは nil。
    return nil
}

/// 末尾カンマ・制御文字・欠けた } を直してパース成功率を上げる。
func repairJSONString(_ s: String) -> String {
    var t = s
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    // 制御文字除去（\u{0000} 等。\t \n は残す）
    t = String(t.unicodeScalars.filter { scalar in
        let v = scalar.value
        if v <= 0x1F { return v == 0x09 || v == 0x0A || v == 0x0D }
        if v == 0x7F { return false }
        return true
    })
    // 末尾カンマ除去: ,} ,] および改行挟み
    t = t.replacingOccurrences(of: ",\n}", with: "\n}")
        .replacingOccurrences(of: ",\n]", with: "\n]")
        .replacingOccurrences(of: ",}", with: "}")
        .replacingOccurrences(of: ",]", with: "]")
    // 末尾の } が足りないときは補う（括弧深度で）
    let openCount = t.filter { $0 == "{" }.count
    let closeCount = t.filter { $0 == "}" }.count
    if openCount > closeCount {
        t += String(repeating: "}", count: openCount - closeCount)
    }
    return t
}

/// 文字列から「最初の { 〜 最後の }」を抜き出して返す（失敗時は throw）。
/// Gemini が「ここからJSONです」等を付けても無視できる。
func extractJSONObjectString(_ text: String) throws -> String {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}"),
          start < end
    else {
        throw JSONExtractionError.noJSONObjectFound
    }
    return String(text[start ... end])
}

/// 素直に decode → 失敗したら { ... } を抽出してから再 decode。
func decodePossiblyWrappedJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
    if let data = text.data(using: .utf8) {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // fallthrough: 抽出して再トライ
        }
    }

    let jsonOnly = try extractJSONObjectString(text)
    guard let data2 = jsonOnly.data(using: .utf8) else {
        throw JSONExtractionError.noJSONObjectFound
    }
    return try JSONDecoder().decode(T.self, from: data2)
}
