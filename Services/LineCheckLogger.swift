//
//  LineCheckLogger.swift
//  GokigenNote
//
//  履歴保存の3点：DONE時・コピー時・フィードバック時。DONEはクライアントで1件追加、コピーは update。
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class LineCheckLogger {
    static let shared = LineCheckLogger()
    private let db = Firestore.firestore()

    private init() {}

    /// DONE時（結果確定）に1件追加。戻り値は documentID（コピー時の logCopy に渡す）
    func logResult(
        uid: String,
        risk: String,
        oneLiner: String,
        suggestions: [[String: String]],
        latencyMs: Int,
        plan: String,
        queueTier: String,
        waitedMs: Int
    ) async -> String? {
        let data: [String: Any] = [
            "createdAt": FieldValue.serverTimestamp(),
            "risk": risk,
            "oneLiner": oneLiner,
            "suggestions": suggestions,
            "latencyMs": latencyMs,
            "planAtTime": plan,
            "queue": [
                "tier": queueTier,
                "waitedMs": waitedMs
            ] as [String: Any]
        ]
        let ref = db.collection("users").document(uid).collection("lineChecks")
        do {
            let docRef = try await ref.addDocument(data: data)
            return docRef.documentID
        } catch {
            return nil
        }
    }

    /// コピー時（行動データ）
    func logCopy(uid: String, checkId: String, label: String, index: Int) async {
        do {
            try await db.collection("users").document(uid)
                .collection("lineChecks").document(checkId)
                .updateData([
                    "selectedLabel": label,
                    "copiedIndex": index,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            // 無視（オフライン等）
        }
    }
}
