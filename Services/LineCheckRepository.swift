//
//  LineCheckRepository.swift
//  GokigenNote
//
//  users/{uid}/lineChecks の購読・更新。
//

import Foundation
import FirebaseFirestore

final class LineCheckRepository {
    static let shared = LineCheckRepository()
    private let db = Firestore.firestore()
    private init() {}

    func listenLatest(uid: String, limit: Int = 50, onChange: @escaping ([LineCheckRecord]) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid)
            .collection("lineChecks")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents, err == nil else {
                    onChange([])
                    return
                }
                let items: [LineCheckRecord] = docs.compactMap { try? $0.data(as: LineCheckRecord.self) }
                onChange(items)
            }
    }

    func updateFeedback(uid: String, checkId: String, feedback: String) async throws {
        try await db.collection("users").document(uid)
            .collection("lineChecks").document(checkId)
            .updateData([
                "sentFeedback": feedback,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func updateCopied(uid: String, checkId: String, selectedLabel: String, copiedIndex: Int) async throws {
        try await db.collection("users").document(uid)
            .collection("lineChecks").document(checkId)
            .updateData([
                "selectedLabel": selectedLabel,
                "copiedIndex": copiedIndex,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
}
