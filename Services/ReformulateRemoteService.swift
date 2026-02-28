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
    func reformulate(text: String, context: ReformulationContext) async throws -> String {
        let params: [String: Any] = [
            "text": text,
            "scene": context.scene.displayName,
            "purpose": context.purpose.rawValue,
            "audience": context.audience.rawValue,
            "tone": context.tone.rawValue,
        ]
        let callable = functions.httpsCallable("reformulate")
        let res = try await callable.call(params)

        guard let data = res.data as? [String: Any],
              let resultText = data["text"] as? String else {
            throw NSError(domain: "ReformulateRemoteService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
