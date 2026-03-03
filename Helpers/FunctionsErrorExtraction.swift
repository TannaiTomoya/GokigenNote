//
//  FunctionsErrorExtraction.swift
//  GokigenNote
//
//  Firebase Callable HttpsError の details から retryAfterSeconds 等を取得する。
//

import Foundation

enum FunctionsErrorExtraction {

    /// HttpsError の details から retryAfterSeconds（Int）を取得する。
    static func retryAfterSeconds(from error: Error) -> Int? {
        let ns = error as NSError
        if let v = ns.userInfo["retryAfterSeconds"] as? Int { return v }
        if let v = ns.userInfo["retryAfterSeconds"] as? Double { return Int(v) }
        for key in ["details", "data"] {
            if let details = ns.userInfo[key] as? [String: Any],
               let v = intFromDetails(details, key: "retryAfterSeconds") { return v }
        }
        return nil
    }

    private static func intFromDetails(_ details: [String: Any], key: String) -> Int? {
        if let v = details[key] as? Int { return v }
        if let v = details[key] as? Double { return Int(v) }
        if let v = details[key] as? String, let i = Int(v) { return i }
        return nil
    }

    /// resource-exhausted かどうか
    static func isResourceExhausted(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "FunctionsErrorDomain", ns.code == 8 { return true }
        if let code = ns.userInfo["code"] as? String, code == "resource-exhausted" { return true }
        let msg = String(describing: error).lowercased()
        return msg.contains("resource-exhausted")
    }

    /// failed-precondition + free_trial_ended（無料7日経過）かどうか
    static func isFreeTrialEnded(_ error: Error) -> Bool {
        let ns = error as NSError
        if let code = ns.userInfo["code"] as? String, code == "free_trial_ended" { return true }
        for key in ["details", "data"] {
            if let details = ns.userInfo[key] as? [String: Any],
               let code = details["code"] as? String, code == "free_trial_ended" { return true }
        }
        return false
    }
}
