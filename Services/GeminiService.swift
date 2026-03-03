//
//  GeminiService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import CryptoKit
import Foundation
import os
@preconcurrency import GoogleGenerativeAI

/// 同一入力のキャッシュキー（改行正規化してハッシュ）
private func makeLineStopperCacheKey(_ text: String) -> String {
    let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let data = Data(normalized.utf8)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}

enum TimeoutError: Error {
    case timedOut(Double)
}

private func withTimeout<T>(
    _ seconds: Double,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut(seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

actor GeminiClient {
    private let model: GenerativeModel

    init(apiKey: String, modelName: String) {
        self.model = GenerativeModel(name: modelName, apiKey: apiKey)
    }

    func generateText(_ prompt: String) async throws -> String {
        let response = try await model.generateContent(prompt)
        return response.text ?? ""
    }
}

struct EmpathyResponse {
    let empathy: String
    let nextStep: String
}

private struct LineStopperAIResponse: Codable {
    let version: Int?
    let language: String?
    let risk: String?
    let riskScore: Int?
    let oneLiner: String?
    let reasons: [String]?
    let suggestions: [LineStopperAISuggestion]?
    struct LineStopperAISuggestion: Codable {
        let label: String
        let text: String
    }
}

final class GeminiService {
    static let shared = GeminiService()
    private let client: GeminiClient?
    private let logger = Logger(subsystem: "GokigenNote", category: "GeminiService")
    private let lineStopperLimiter = RateLimiter(minInterval: 1.2)
    private let lineStopperCache = LineStopperCache(ttl: 60 * 10) // 10分

    init() {
        if let apiKey = APIKey.gemini, !apiKey.isEmpty {
            let masked = String(apiKey.prefix(4)) + "..." + String(apiKey.suffix(4))
            print("[Gemini] init: API key present, masked=\(masked)")
            self.client = GeminiClient(apiKey: apiKey, modelName: "gemini-2.0-flash")
        } else {
            self.client = nil
            print("[Gemini] init: API key nil or empty, client=nil")
            logger.info("Gemini API key not configured. Using local fallback.")
        }
    }

    func generateEmpathy(for text: String) async throws -> EmpathyResponse {
        guard let client else { throw GeminiError.apiKeyNotAvailable }

        logger.info("Requesting empathy generation...")
        let prompt = """
        あなたは、しんどい人に寄り添う日本語のカウンセラーです。

        ユーザーの文章：
        「\(text)」

        以下の2つを日本語で返してください。

        1) 共感メッセージ：
           ユーザーを否定せず、「がんばりを認める」やさしい言葉。

        2) 次の一歩：
           今日できそうな、ハードルの低い一歩。
           例：深呼吸を3回する／温かい飲み物を飲む など。
        """
        print("[Gemini] API Request: generateEmpathy, text=\(text)")

        do {
            let raw = try await withTimeout(15) { [client] in
                try await client.generateText(prompt)
            }
            print("[Gemini] API Response: empathy, ok")
            print("[Gemini] TEXT: \(raw.isEmpty ? "empty" : raw)")
            logger.info("Empathy generation completed.")

            if raw.isEmpty {
                print("[Gemini] WARN: response.text is empty")
            }

            // 複数の区切りパターンに対応（"2)" "2）" "2." "②" "**2)" "**2）"）
            let splitPattern = #"(?:\*{0,2})(?:2[)）.]|②)"#
            let parts = raw.split(
                separator: try! Regex(splitPattern),
                maxSplits: 1
            )

            let empathy: String
            let nextStep: String

            if parts.count > 1 {
                empathy = String(parts[0])
                nextStep = String(parts[1])
            } else {
                empathy = raw
                nextStep = "今日はゆっくり休むだけで十分です。"
            }

            let cleanEmpathy = empathy
                .replacingOccurrences(of: #"^[\s\*]*(?:1[)）.]|①)[\s]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanNextStep = nextStep
                .replacingOccurrences(of: #"^[\s\*]*(?:次の一歩[：:]?)[\s]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return EmpathyResponse(
                empathy: cleanEmpathy.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleanEmpathy,
                nextStep: cleanNextStep.isEmpty ? "今日はゆっくり休むだけで十分です。" : cleanNextStep
            )
        } catch {
            let ns = error as NSError
            print("[Gemini] ERROR generateEmpathy: \(error)")
            print("[Gemini] NSError domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }

    /// 言い換え: Functions の reformulate を呼ぶ（キーはサーバ側のみ・アプリに渡さない）。limitsPayload は UI の「あと○回」同期用。
    func reformulateText(for text: String, context: ReformulationContext) async throws -> (result: String, isFallback: Bool, limitsPayload: [String: Any]?) {
        logger.info("Requesting text reformulation via Functions...")
        let tuple = try await ReformulateRemoteService.shared.reformulate(text: text, context: context)
        logger.info("Text reformulation completed.")
        return tuple
    }

    /// 地雷LINEストッパー: キャッシュ → レート制限（補助輪）→ Functions lineStopper 呼び出し（キー・RPM はサーバ）。返却に queueTier を含む。limitsPayload は UI の「あと○回」同期用（キャッシュヒット時は nil）。
    func generateLineStopperResult(text: String) async throws -> (riskRaw: String, oneLiner: String, suggestions: [(label: String, text: String)], queueTier: String, limitsPayload: [String: Any]?) {
        let key = makeLineStopperCacheKey(text)
        if let cached = await lineStopperCache.get(key) {
            return (cached.value.0, cached.value.1, cached.value.2, cached.value.3, nil)
        }

        await lineStopperLimiter.acquire()
        do {
            let (remote, limitsPayload) = try await LineStopperRemoteService.shared.check(text: text)
            let result = (remote.riskRaw, remote.oneLiner, remote.suggestions, remote.queueTier.rawValue)
            await lineStopperCache.set(key, .init(value: result, createdAt: Date()))
            await lineStopperLimiter.release()
            return (remote.riskRaw, remote.oneLiner, remote.suggestions, remote.queueTier.rawValue, limitsPayload)
        } catch {
            await lineStopperLimiter.release()
            throw error
        }
    }

    /// 既存ロジック: 危険度 + 改善案3つを JSON で返す（壊れにくいプロンプト・抽出・1回リトライ）
    private func generateLineStopperResult_core(text: String) async throws -> (riskRaw: String, oneLiner: String, suggestions: [(label: String, text: String)]) {
        guard let client else { throw GeminiError.apiKeyNotAvailable }

        let normalizedInput = normalizeLineStopperInput(text)
        let prompt = buildLineStopperPrompt(inputText: normalizedInput)

        func tryGenerate(_ prompt: String) async throws -> String {
            try await withTimeout(20) { [client] in
                try await client.generateText(prompt)
            }
        }

        // 1st try
        let raw1 = try await tryGenerate(prompt)
        var decoded = decodeLineStopper(from: raw1)

        // Retry with REPAIR prompt if failed
        if decoded == nil {
            let repairPrompt = buildLineStopperRepairPrompt(inputText: normalizedInput, rawOutput: raw1)
            let raw2 = try await tryGenerate(repairPrompt)
            decoded = decodeLineStopper(from: raw2)

            if decoded == nil {
                print("[Gemini] LineStopper JSON decode failed after retry. RAW1: \(raw1.prefix(200))...")
            }
        }

        let final = decoded ?? fallbackResponse(input: text)

        let risk = (final.risk ?? "LOW").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let riskRaw: String = ["HIGH", "MEDIUM", "LOW"].contains(risk) ? risk : "LOW"

        let one = (final.oneLiner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let oneLinerSafe = one.isEmpty ? "送信前に一度確認してみましょう。" : one

        let list = (final.suggestions ?? []).prefix(3).map { ($0.label, $0.text) }

        let fallbackSuggestions: [(label: String, text: String)] = [
            ("柔らかく", "ちょっと気になってることがあるんだけど、時間あるときに話せる？"),
            ("余裕", "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな"),
            ("距離", "一旦この話は置いておくね。またタイミング合うときに話そう")
        ]

        let suggestions: [(label: String, text: String)] = list.count >= 3 ? Array(list) : fallbackSuggestions

        return (riskRaw: riskRaw, oneLiner: oneLinerSafe, suggestions: suggestions)
    }

    /// 抽出 → decode → 失敗時は repair → sanitize → 再 decode。
    private func decodeLineStopper(from raw: String) -> LineStopperAIResponse? {
        guard let extracted = extractJSON(from: raw) else { return nil }

        if let data = extracted.data(using: .utf8),
           let ok = try? JSONDecoder().decode(LineStopperAIResponse.self, from: data) {
            return ok
        }

        let repaired = repairJSONString(extracted)
        let sanitized = sanitizeLineStopperJSON(repaired) ?? repaired

        guard let data2 = sanitized.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(LineStopperAIResponse.self, from: data2)
        } catch {
            print("[Gemini] LineStopper JSON decode failed:", error)
            return nil
        }
    }

    /// JSON として正規化（risk/oneLiner を String に、suggestions を 3 件に整形）。パースできない場合は nil。
    private func sanitizeLineStopperJSON(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              var dict = obj as? [String: Any] else { return nil }

        let riskStr: String = {
            if let s = dict["risk"] as? String {
                let u = s.uppercased()
                return ["LOW", "MEDIUM", "HIGH"].contains(u) ? u : "LOW"
            }
            return "LOW"
        }()
        dict["risk"] = riskStr

        let oneLinerStr: String = {
            if let s = dict["oneLiner"] as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "送信前に一度確認してみましょう。" : trimmed
            }
            return "送信前に一度確認してみましょう。"
        }()
        dict["oneLiner"] = oneLinerStr

        let fallback: [[String: String]] = [
            ["label": "柔らかく", "text": "ちょっと気になってることがあるんだけど、時間あるときに話せる？"],
            ["label": "余裕", "text": "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな"],
            ["label": "距離", "text": "一旦この話は置いておくね。またタイミング合うときに話そう"]
        ]

        var cleaned: [[String: String]] = []
        if let arr = dict["suggestions"] as? [Any] {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                guard let label = d["label"] as? String,
                      let text = d["text"] as? String else { continue }
                let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if l.isEmpty || t.isEmpty { continue }
                cleaned.append(["label": String(l.prefix(10)), "text": t])
                if cleaned.count == 3 { break }
            }
        }
        if cleaned.count < 3 {
            for i in cleaned.count ..< 3 {
                cleaned.append(fallback[i])
            }
        }
        dict["suggestions"] = cleaned

        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let outStr = String(data: out, encoding: .utf8) else { return nil }
        return outStr
    }

    /// JSON 壊れ時は最低限の価値を返す（絶対に落とさない）。
    private func fallbackResponse(input: String) -> LineStopperAIResponse {
        LineStopperAIResponse(
            version: nil,
            language: nil,
            risk: "MEDIUM",
            riskScore: nil,
            oneLiner: "少し強く伝わる可能性があります",
            reasons: nil,
            suggestions: [
                .init(label: "柔らかく", text: "ちょっと気になってることがあるんだけど、時間あるときに話せる？"),
                .init(label: "余裕", text: "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな"),
                .init(label: "距離", text: "一旦この話は置いておくね。またタイミング合うときに話そう")
            ]
        )
    }

    private func buildLineStopperPrompt(inputText: String) -> String {
        return """
        あなたは「送信前LINEチェック」専用の文章コーチです。
        入力文を評価し、後悔リスクと、コピペ可能な改善案を3つ出します。

        【入力文】
        \(inputText)

        【出力ルール（最重要）】
        - 出力は必ず <OUTPUT> と </OUTPUT> で囲んでください。
        - <OUTPUT> の中身は JSON 1個だけ。
        - <OUTPUT> の外には文字を一切出力しない（説明・挨拶・コードフェンス・マークダウン禁止）。

        【JSON制約】
        - JSONのキーは必ず次の3つのみ：risk, oneLiner, suggestions
        - risk は "LOW" / "MEDIUM" / "HIGH" のいずれか（必ず大文字）
        - oneLiner は 40文字以内の日本語1文
        - suggestions は要素3個ちょうど
        - suggestions[i] は { "label": "...", "text": "..." } のみ
        - label は10文字以内、text は1〜2文でコピペ可能、日本語、敬語寄り
        - 文字列は必ずダブルクォート（シングルクォート禁止）
        - 末尾カンマ禁止

        【出力例（この形を厳守）】
        <OUTPUT>{"risk":"LOW","oneLiner":"...","suggestions":[{"label":"...","text":"..."},{"label":"...","text":"..."},{"label":"...","text":"..."}]}</OUTPUT>
        """
    }

    /// 長文・改行だらけで崩れ率が上がるのを防ぐ。先頭末尾空白削除・改行圧縮・文字数上限。
    private func normalizeLineStopperInput(_ text: String) -> String {
        let maxLength = 800
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        if s.count > maxLength {
            s = String(s.prefix(maxLength)) + "（以下略）"
        }
        return s
    }

    private func buildLineStopperRepairPrompt(inputText: String, rawOutput: String) -> String {
        """
        あなたは JSON 修復機です。次の出力を、指定スキーマの **正しいJSONだけ** に修復してください。

        【入力文】
        \(inputText)

        【壊れた出力】
        \(rawOutput)

        【修復ルール（最重要）】
        - 出力は JSON 1個だけ。説明・前置き・コードフェンス禁止。
        - キーは risk, oneLiner, suggestions のみ（余計なキー削除）。
        - risk は "LOW" / "MEDIUM" / "HIGH" の大文字。
        - oneLiner は 40文字以内。
        - suggestions は3個ちょうど。各要素は { "label": "...", "text": "..." } のみ。
        - JSONとしてパースできること。ダブルクォート必須。末尾カンマ禁止。

        【出力JSONの形】
        {"risk":"LOW","oneLiner":"...","suggestions":[{"label":"...","text":"..."},{"label":"...","text":"..."},{"label":"...","text":"..."}]}
        """
    }
}

enum GeminiError: Error, LocalizedError {
    case apiKeyNotAvailable

    var errorDescription: String? {
        switch self {
        case .apiKeyNotAvailable:
            return "APIキーが未設定です。サーバー設定をご確認ください。"
        }
    }
}
