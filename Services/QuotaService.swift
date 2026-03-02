//
//  QuotaService.swift
//  GokigenNote
//
//  P1A: consumeRewrite でサーバが回数制限・課金判定。チート不可。
//

import Foundation
import FirebaseFunctions

enum QuotaOp: String {
    case reformulate
    case empathy
}

struct QuotaCheckResult: Equatable {
    let allowed: Bool
    let plan: String
    let limit: Int
    let used: Int
    let remaining: Int
    let resetKey: String
    let reason: String?
    let paywall: Bool
    /// 無料ユーザー連打制限: クールダウン残り秒数（reason == "cooldown" のときのみ）
    let cooldownRemainingSeconds: Int?
}

final class QuotaService {
    static let shared = QuotaService()

    private let functions = Functions.functions(region: "asia-northeast1")
    private init() {}

    /// Functions が unauthenticated で返したか（未ログイン時は true → サインイン誘導）
    static func isUnauthenticated(_ error: Error) -> Bool {
        let ns = error as NSError
        if let code = ns.userInfo["code"] as? String, code == "unauthenticated" { return true }
        if ns.domain == "FunctionsErrorDomain", ns.code == 1 { return true }
        return ns.localizedDescription.lowercased().contains("unauthenticated")
    }

    /// resource-exhausted（レート制限）かどうか
    static func isResourceExhausted(_ error: Error) -> Bool {
        let ns = error as NSError
        if let code = ns.userInfo["code"] as? String, code == "resource-exhausted" { return true }
        return ns.localizedDescription.lowercased().contains("rate limit") || ns.localizedDescription.lowercased().contains("resource-exhausted")
    }

    /// 地雷LINEストッパー用: 1分あたりN回のサーバ側ガード。通過すれば OK、超過時は resource-exhausted で throw。
    func consumeLineStopper() async throws {
        let callable = functions.httpsCallable("consumeLineStopper")
        _ = try await callable.call([:])
    }

    /// P1A: consumeRewrite を呼ぶ。allowed:false なら AI は叩かず Paywall 表示。
    func consumeRewrite(op: QuotaOp, draftEntryId: String? = nil) async throws -> QuotaCheckResult {
        var data: [String: Any] = ["op": op.rawValue]
        if let id = draftEntryId, !id.isEmpty {
            data["draftEntryId"] = id
        }

        let callable = functions.httpsCallable("consumeRewrite")
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any] else {
            throw NSError(domain: "QuotaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        let allowed = (dict["allowed"] as? Bool) ?? false
        let plan = (dict["plan"] as? String) ?? "free"
        // サーバーは RateLimitDetails で daily: { limit, used, remaining, resetAtMs } を返す
        let daily = dict["daily"] as? [String: Any]
        let limit = (daily?["limit"] as? Int) ?? (dict["limit"] as? Int) ?? 0
        let used = (daily?["used"] as? Int) ?? (dict["used"] as? Int) ?? 0
        let remaining = (daily?["remaining"] as? Int) ?? (dict["remaining"] as? Int) ?? 0
        let resetAtMsVal = daily?["resetAtMs"]
        let resetKey: String = {
            if let i = resetAtMsVal as? Int { return "\(i)" }
            if let d = resetAtMsVal as? Double { return "\(Int(d))" }
            return (dict["resetKey"] as? String) ?? ""
        }()
        let reason = dict["reason"] as? String
        let paywall = (dict["paywall"] as? Bool) ?? (!allowed && reason != nil)
        let rawRetry = dict["retryAfterSeconds"] ?? dict["cooldownRemainingSeconds"]
        let cooldownRemainingSeconds: Int? = (rawRetry as? Int) ?? (rawRetry as? Double).map { Int($0) }

        return QuotaCheckResult(
            allowed: allowed,
            plan: plan,
            limit: limit,
            used: used,
            remaining: remaining,
            resetKey: resetKey,
            reason: reason,
            paywall: paywall,
            cooldownRemainingSeconds: cooldownRemainingSeconds
        )
    }
}
