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
        let limit = (dict["limit"] as? Int) ?? 0
        let used = (dict["used"] as? Int) ?? 0
        let remaining = (dict["remaining"] as? Int) ?? 0
        let resetKey = (dict["resetKey"] as? String) ?? ""
        let reason = dict["reason"] as? String
        let paywall = (dict["paywall"] as? Bool) ?? false

        return QuotaCheckResult(
            allowed: allowed,
            plan: plan,
            limit: limit,
            used: used,
            remaining: remaining,
            resetKey: resetKey,
            reason: reason,
            paywall: paywall
        )
    }
}
