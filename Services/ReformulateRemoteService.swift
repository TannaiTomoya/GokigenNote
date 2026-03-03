//
//  ReformulateRemoteService.swift
//  GokigenNote
//
//  言い換え: Functions の reformulate を呼ぶ（キーはサーバ側のみ）
//

import Foundation
import FirebaseFunctions

final class ReformulateRemoteService {
    static let shared = ReformulateRemoteService()

    private let functions = Functions.functions(region: "asia-northeast1")

    private init() {}

    /// サーバで Gemini 言い換え。キーはアプリに持たせない。
    /// - Returns: 言い換え結果、フォールバックか、および UI の「あと○回」同期用 limits（CF が返した場合のみ）。
    func reformulate(text: String, context: ReformulationContext) async throws -> (result: String, isFallback: Bool, limitsPayload: [String: Any]?) {
        let tier = PremiumManager.shared.queueTier.rawValue
        let params: [String: Any] = [
            "text": text,
            "scene": context.scene.displayName,
            "purpose": context.purpose.rawValue,
            "audience": context.audience.rawValue,
            "tone": context.tone.rawValue,
            "isYearly": context.isYearly,
            "queueTier": tier,
        ]
        let callable = functions.httpsCallable("reformulate")
        let res = try await callable.call(params)

        guard let data = res.data as? [String: Any],
              let resultText = data["text"] as? String else {
            throw NSError(domain: "ReformulateRemoteService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        let isFallback = (data["fallback"] as? Bool) ?? false
        let limitsPayload = data["limits"] as? [String: Any]
        return (resultText.trimmingCharacters(in: .whitespacesAndNewlines), isFallback, limitsPayload)
    }
}

