//
//  LineStopperRemoteService.swift
//  GokigenNote
//
//  地雷LINEストッパー: Functions の lineStopper を呼ぶ（キー・RPM はサーバ側）
//

import Foundation
import FirebaseFunctions

final class LineStopperRemoteService {
    static let shared = LineStopperRemoteService()

    private let functions = Functions.functions(region: "asia-northeast1")

    struct LineStopperAIResponse: Codable {
        let risk: String
        let oneLiner: String
        let suggestions: [Suggestion]?
        struct Suggestion: Codable {
            let label: String
            let text: String
        }
    }

    private init() {}

    /// サーバでレート制限 + Gemini 実行。返却は risk / oneLiner / suggestions。
    func check(text: String) async throws -> (riskRaw: String, oneLiner: String, suggestions: [(label: String, text: String)]) {
        let callable = functions.httpsCallable("lineStopper")
        let res = try await callable.call(["text": text])

        guard let data = res.data as? [String: Any] else {
            throw NSError(domain: "LineStopperRemoteService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        let riskRaw = (data["risk"] as? String) ?? "LOW"
        let oneLiner = (data["oneLiner"] as? String) ?? "送信前に一度確認してみましょう。"

        let fallbackSuggestions: [(label: String, text: String)] = [
            ("柔らかく", "ちょっと気になってることがあるんだけど、時間あるときに話せる？"),
            ("余裕", "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな"),
            ("距離", "一旦この話は置いておくね。またタイミング合うときに話そう"),
        ]

        var suggestions: [(label: String, text: String)] = []
        if let arr = data["suggestions"] as? [[String: Any]] {
            for item in arr {
                guard let label = item["label"] as? String, let text = item["text"] as? String,
                      !label.isEmpty, !text.isEmpty else { continue }
                suggestions.append((label, text))
                if suggestions.count >= 3 { break }
            }
        }
        if suggestions.count < 3 {
            suggestions = fallbackSuggestions
        }

        return (riskRaw: riskRaw, oneLiner: oneLiner, suggestions: suggestions)
    }
}
