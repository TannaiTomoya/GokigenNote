//
//  RateLimiter.swift
//  GokigenNote
//
//  1リクエスト実行中はブロック & 最低間隔を保証（RPM超過防止）
//

import Foundation

actor RateLimiter {
    private var lastFireAt: Date?
    private var inFlight = false

    /// 例: 1.2秒に1回まで。連打/二重実行を止める。
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval = 1.2) {
        self.minInterval = minInterval
    }

    func acquire() async {
        // 同時実行を禁止（1つが終わるまで待つ）
        while inFlight {
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
        }

        // 最低間隔を保証
        if let last = lastFireAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                let wait = minInterval - elapsed
                let ns = UInt64(wait * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }

        inFlight = true
        lastFireAt = Date()
    }

    func release() {
        inFlight = false
    }
}
