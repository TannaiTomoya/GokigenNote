//
//  LineStopperCache.swift
//  GokigenNote
//
//  同一入力の無駄打ち防止（メモリキャッシュ・TTL付き）
//

import Foundation

actor LineStopperCache {
    struct Entry {
        let value: (riskRaw: String, oneLiner: String, suggestions: [(label: String, text: String)])
        let createdAt: Date
    }

    private var store: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 60 * 10) { // 10分
        self.ttl = ttl
    }

    func get(_ key: String) -> Entry? {
        guard let e = store[key] else { return nil }
        if Date().timeIntervalSince(e.createdAt) > ttl {
            store.removeValue(forKey: key)
            return nil
        }
        return e
    }

    func set(_ key: String, _ value: Entry) {
        store[key] = value
    }
}
