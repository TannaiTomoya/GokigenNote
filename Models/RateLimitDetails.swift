//
//  RateLimitDetails.swift
//  GokigenNote
//
//  Functions が返す details の統一形（Callable 成功時・resource-exhausted 時どちらも同じ形）。
//

import Foundation

struct RateLimitWindow: Codable {
    let limit: Int
    let windowSeconds: Int?
    let used: Int
    let remaining: Int
    let resetAtMs: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limit = try c.decodeInt(forKey: .limit)
        windowSeconds = try c.decodeIntIfPresent(forKey: .windowSeconds)
        used = try c.decodeInt(forKey: .used)
        remaining = try c.decodeInt(forKey: .remaining)
        resetAtMs = try c.decodeDouble(forKey: .resetAtMs)
    }

    private enum CodingKeys: String, CodingKey { case limit, windowSeconds, used, remaining, resetAtMs }
}

struct RateLimitDetails: Codable {
    let allowed: Bool
    let plan: String
    let tier: String
    let op: String
    let daily: RateLimitWindow
    let rpm: RateLimitWindow
    let retryAfterSeconds: Int?
    let reason: String?

    var queueTier: QueueTier {
        QueueTier(rawValue: tier) ?? .standard
    }
}

private extension KeyedDecodingContainer {
    func decodeInt(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let d = try? decode(Double.self, forKey: key) { return Int(d) }
        throw DecodingError.typeMismatch(Int.self, .init(codingPath: codingPath + [key], debugDescription: "expected Int or Double"))
    }
    func decodeIntIfPresent(forKey key: Key) throws -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let d = try? decode(Double.self, forKey: key) { return Int(d) }
        return nil
    }
    func decodeDouble(forKey key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        throw DecodingError.typeMismatch(Double.self, .init(codingPath: codingPath + [key], debugDescription: "expected Double or Int"))
    }
}
