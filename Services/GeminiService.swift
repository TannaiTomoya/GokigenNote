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
            self.model = GenerativeModel(name: "gemini-2.5-flash-lite", apiKey: apiKey)
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
        let parts = fullText.components(separatedBy: "2)")
        let empathy = parts.first ?? fullText
        let nextStep = parts.count > 1 ? parts[1] : "今日はゆっくり休むだけで十分です。"

        return EmpathyResponse(
            empathy: empathy.trimmingCharacters(in: .whitespacesAndNewlines),
            nextStep: nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    
    // 言語化が苦手な人のための文章整形機能
    func reformulateText(for text: String) async throws -> String {
        guard let model = model else {
            throw GeminiError.apiKeyNotAvailable
        }
        
        logger.info("Requesting text reformulation...")
        let prompt = """
        あなたは、言語化が苦手な人をサポートする優しい日本語アシスタントです。

        ユーザーが入力した文章：
        「\(text)」

        この文章を、以下の点に注意して綺麗に言語化してください：

        1) ユーザーの気持ちや考えを正確に理解し、それを明確に表現する
        2) 自然で読みやすい日本語にする
        3) ユーザーの意図を変えずに、より伝わりやすい表現にする
        4) 必要に応じて、曖昧な部分を補完する
        5) 文章を一つにまとめて、簡潔に表現する

        注意：説明や前置きは不要です。整形した文章だけを返してください。
        """

        let response = try await model.generateContent(prompt)
        logger.info("Text reformulation completed.")
        let reformulatedText = response.text ?? text
        
        return reformulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GeminiError: Error {
    case apiKeyNotAvailable
}
