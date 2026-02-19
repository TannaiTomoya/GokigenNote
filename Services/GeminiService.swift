//
//  GeminiService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import Foundation
import GoogleGenerativeAI
import os


struct EmpathyResponse {
    let empathy: String
    let nextStep: String
}

final class GeminiService {
    private let model: GenerativeModel?
    private let logger = Logger(subsystem: "GokigenNote", category: "GeminiService")

    init() {
        if let apiKey = APIKey.gemini, !apiKey.isEmpty {
            self.model = GenerativeModel(name: "gemini-2.0-flash", apiKey: apiKey)
        } else {
            self.model = nil
            logger.info("Gemini API key not configured. Using local fallback.")
        }
    }

    func generateEmpathy(for text: String) async throws -> EmpathyResponse {
        guard let model = model else {
            throw GeminiError.apiKeyNotAvailable
        }
        
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

        let response = try await model.generateContent(prompt)
        logger.info("Empathy generation completed.")
        let fullText = response.text ?? ""

        // 複数の区切りパターンに対応（"2)" "2）" "2." "②" "**2)" "**2）"）
        let splitPattern = #"(?:\*{0,2})(?:2[)）.]|②)"#
        let parts = fullText.split(
            separator: try! Regex(splitPattern),
            maxSplits: 1
        )

        let empathy: String
        let nextStep: String

        if parts.count > 1 {
            empathy = String(parts[0])
            nextStep = String(parts[1])
        } else {
            // 区切りが見つからない場合: 全体を共感メッセージとしフォールバック
            empathy = fullText
            nextStep = "今日はゆっくり休むだけで十分です。"
        }

        // "1)" 等のプレフィックスも除去
        let cleanEmpathy = empathy
            .replacingOccurrences(of: #"^[\s\*]*(?:1[)）.]|①)[\s]*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "次の一歩：" 等のラベルを除去
        let cleanNextStep = nextStep
            .replacingOccurrences(of: #"^[\s\*]*(?:次の一歩[：:]?)[\s]*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return EmpathyResponse(
            empathy: cleanEmpathy.isEmpty ? fullText.trimmingCharacters(in: .whitespacesAndNewlines) : cleanEmpathy,
            nextStep: cleanNextStep.isEmpty ? "今日はゆっくり休むだけで十分です。" : cleanNextStep
        )
    }
    
    // 言語化が苦手な人のための文章整形機能（目的・相手・トーン指定あり）
    func reformulateText(for text: String, context: ReformulationContext = .default) async throws -> String {
        guard let model = model else {
            throw GeminiError.apiKeyNotAvailable
        }
        
        logger.info("Requesting text reformulation...")
        let prompt = """
        あなたは、言語化が苦手な人をサポートする優しい日本語アシスタントです。

        ユーザーが入力した文章：
        「\(text)」

        【伝え方の指定】
        - 目的：\(context.purpose.rawValue)
        - 相手：\(context.audience.rawValue)
        - トーン：\(context.tone.rawValue)

        上記の指定に沿って、この文章を綺麗に言語化してください。

        1) ユーザーの気持ちや考えを正確に理解し、指定の目的・相手・トーンに合う表現にする
        2) 自然で読みやすい日本語にする
        3) ユーザーの意図を変えずに、より伝わりやすい表現にする
        4) 必要に応じて、曖昧な部分を補完する
        5) 文章を一つにまとめて、簡潔に表現する（200文字以内）

        【重要】説明や前置きは不要です。整形した文章だけを返してください。
        【重要】「整形した文章：」などのラベルも不要です。文章のみを返してください。
        """

        let response = try await model.generateContent(prompt)
        logger.info("Text reformulation completed.")
        var reformulatedText = response.text ?? text
        
        // 余計な接頭辞を削除
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
    }
}

enum GeminiError: Error {
    case apiKeyNotAvailable
}
