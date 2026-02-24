//
//  GeminiService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import Foundation
import os
@preconcurrency import GoogleGenerativeAI

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

final class GeminiService {
    private let client: GeminiClient?
    private let logger = Logger(subsystem: "GokigenNote", category: "GeminiService")

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

    func reformulateText(for text: String, context: ReformulationContext) async throws -> String {
        guard let client else { throw GeminiError.apiKeyNotAvailable }

        logger.info("Requesting text reformulation...")
        let sceneName = context.scene.displayName
        let prompt = """
        以下の発言を「\(sceneName)」の場面で自然に伝わる表現に言い換えてください。

        ・相手に伝わる
        ・誤解されない
        ・簡潔

        【追加の指定】
        - 目的：\(context.purpose.rawValue)
        - 相手：\(context.audience.rawValue)
        - トーン：\(context.tone.rawValue)

        入力:
        \(text)

        上記に沿って言語化し、200文字以内でまとめてください。説明やラベルは不要です。文章のみを返してください。
        """
        print("[Gemini] API Request: reformulateText, text=\(text), scene=\(sceneName), purpose=\(context.purpose.rawValue), audience=\(context.audience.rawValue), tone=\(context.tone.rawValue)")

        do {
            let raw = try await withTimeout(15) { [client] in
                try await client.generateText(prompt)
            }
            print("[Gemini] API Response: reformulateText, ok")
            print("[Gemini] TEXT: \(raw.isEmpty ? "empty" : raw)")
            logger.info("Text reformulation completed.")

            var reformulatedText = raw.isEmpty ? text : raw
            if raw.isEmpty {
                print("[Gemini] WARN: response.text is empty, using input as fallback")
            }

            let unwantedPrefixes = [
                "整形した文章：",
                "整形した文章:",
                "言い換え：",
                "言い換え:",
                "回答：",
                "回答:",
                "「",
                "」"
            ]

            for prefix in unwantedPrefixes {
                if reformulatedText.hasPrefix(prefix) {
                    reformulatedText = String(reformulatedText.dropFirst(prefix.count))
                }
                if reformulatedText.hasSuffix(prefix) {
                    reformulatedText = String(reformulatedText.dropLast(prefix.count))
                }
            }

            return reformulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let ns = error as NSError
            print("[Gemini] ERROR reformulateText: \(error)")
            print("[Gemini] NSError domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }
}

enum GeminiError: Error {
    case apiKeyNotAvailable
}
