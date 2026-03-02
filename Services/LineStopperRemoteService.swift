//
//  LineStopperRemoteService.swift
//  GokigenNote
//
//  地雷LINEストッパー: enqueueLineStopper → ポーリング getJobResult。返却に queueTier を含む。
//

import Foundation
import Combine
import FirebaseFunctions

/// チェック結果（queueTier は Functions 返却で UI の出し分けに使用）
struct LineStopperRemoteResult {
    let riskRaw: String
    let oneLiner: String
    let suggestions: [(label: String, text: String)]
    let queueTier: QueueTier
}

@MainActor
final class LineStopperRemoteService: ObservableObject {
    static let shared = LineStopperRemoteService()

    @Published private(set) var progress: LineStopperProgress = .idle
    /// enqueue 返却の queueTier（UIラベル用。正は PremiumManager.plan）
    @Published private(set) var lastQueueTier: QueueTier = .standard

    private let functions = Functions.functions(region: "asia-northeast1")
    private let pollInterval: TimeInterval = 0.5
    private let pollTimeout: TimeInterval = 12

    private init() {}

    func resetProgress() {
        progress = .idle
        lastQueueTier = .standard
    }

    /// enqueue → 年額なら即 DONE 返却、それ以外は jobId でポーリング。
    func check(text: String) async throws -> LineStopperRemoteResult {
        progress = .waiting(seconds: 0)

        let enqueueCallable = functions.httpsCallable("enqueueLineStopper")
        let res = try await enqueueCallable.call(["text": text])

        guard let data = res.data as? [String: Any],
              let status = data["status"] as? String,
              let queueTierRaw = data["queueTier"] as? String else {
            progress = .idle
            throw NSError(domain: "LineStopperRemoteService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid enqueue response"])
        }
        let tier = QueueTier(rawValue: queueTierRaw) ?? .standard
        lastQueueTier = tier

        // 年額同期: status == "DONE" で result が返っている → ポーリング不要
        if status == "DONE", let result = data["result"] as? [String: Any] {
            progress = .done
            return parseResult(result, queueTier: tier)
        }

        // キュー投入済み: jobId でポーリング
        guard let jobId = data["jobId"] as? String else {
            progress = .idle
            throw NSError(domain: "LineStopperRemoteService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing jobId"])
        }

        let start = Date()
        let getResult = functions.httpsCallable("getJobResult")

        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            let elapsed = Int(Date().timeIntervalSince(start))

            if elapsed >= 5 {
                progress = .processing
            } else {
                progress = .waiting(seconds: elapsed)
            }

            if Double(elapsed) > pollTimeout {
                progress = .idle
                throw NSError(domain: "LineStopperRemoteService", code: -4, userInfo: [NSLocalizedDescriptionKey: "混雑中のため時間がかかっています。しばらくしてからお試しください。"])
            }

            let resultRes = try await getResult.call(["jobId": jobId])
            guard let resultData = resultRes.data as? [String: Any],
                  let pollStatus = resultData["status"] as? String else {
                continue
            }
            let jobTierRaw = (resultData["queueTier"] as? String) ?? queueTierRaw
            let jobTier = QueueTier(rawValue: jobTierRaw) ?? tier
            lastQueueTier = jobTier

            switch pollStatus {
            case "DONE":
                progress = .done
                guard let result = resultData["result"] as? [String: Any] else {
                    return parseResult([:], queueTier: jobTier)
                }
                return parseResult(result, queueTier: jobTier)
            case "FAILED":
                progress = .idle
                let errorMsg = (resultData["error"] as? String) ?? "Job failed"
                throw NSError(domain: "LineStopperRemoteService", code: -3, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            case "QUEUED", "RUNNING":
                continue
            default:
                continue
            }
        }
    }

    private func parseResult(_ result: [String: Any], queueTier: QueueTier) -> LineStopperRemoteResult {
        let riskRaw = (result["risk"] as? String) ?? "LOW"
        let oneLiner = (result["oneLiner"] as? String) ?? "送信前に一度確認してみましょう。"

        var suggestions: [(label: String, text: String)] = []
        if let arr = result["suggestions"] as? [[String: Any]] {
            for item in arr {
                guard let label = item["label"] as? String, let text = item["text"] as? String,
                      !label.isEmpty, !text.isEmpty else { continue }
                suggestions.append((label, text))
                if suggestions.count >= 3 { break }
            }
        }
        if suggestions.count < 3 {
            suggestions = fallbackSuggestions()
        }
        return LineStopperRemoteResult(riskRaw: riskRaw, oneLiner: oneLiner, suggestions: suggestions, queueTier: queueTier)
    }

    private func fallbackSuggestions() -> [(label: String, text: String)] {
        [
            ("柔らかく", "ちょっと気になってることがあるんだけど、時間あるときに話せる？"),
            ("余裕", "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな"),
            ("距離", "一旦この話は置いておくね。またタイミング合うときに話そう"),
        ]
    }

}
