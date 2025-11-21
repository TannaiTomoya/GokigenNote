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
            self.model = GenerativeModel(name: "gemini-1.5-flash", apiKey: apiKey)
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
}

enum GeminiError: Error {
    case apiKeyNotAvailable
}
