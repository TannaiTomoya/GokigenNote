//
//  FunctionsErrorParser.swift
//  GokigenNote
//
//  Firebase Callable の resource-exhausted を検知し、details を RateLimitDetails にデコードする。
//

import Foundation

enum FunctionsErrorKind {
    case resourceExhausted(details: RateLimitDetails, tier: QueueTier)
    case other(message: String)
}

enum FunctionsErrorParser {
    private static let functionsErrorDomain = "FunctionsErrorDomain"
    private static let resourceExhaustedCode = 8

    static func parse(_ error: Error) -> FunctionsErrorKind? {
        let ns = error as NSError
        guard ns.domain == functionsErrorDomain, ns.code == resourceExhaustedCode else {
            if let code = ns.userInfo["code"] as? String, code == "resource-exhausted",
               let details = decodeDetails(ns.userInfo) {
                let tier = QueueTier(rawValue: details.tier) ?? .standard
                return .resourceExhausted(details: details, tier: tier)
            }
            return nil
        }
        guard let details = decodeDetails(ns.userInfo) else {
            return nil
        }
        let tier = QueueTier(rawValue: details.tier) ?? .standard
        return .resourceExhausted(details: details, tier: tier)
    }

    /// resource-exhausted を処理したかどうか（parse して .resourceExhausted なら true）
    static func isResourceExhausted(_ error: Error) -> Bool {
        parse(error) != nil
    }

    private static func decodeDetails(_ userInfo: [String: Any]) -> RateLimitDetails? {
        let dict: [String: Any]?
        if let d = userInfo["details"] as? [String: Any] {
            dict = d
        } else {
            dict = userInfo
        }
        guard let dict else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(RateLimitDetails.self, from: data)
        } catch {
            return nil
        }
    }
}
