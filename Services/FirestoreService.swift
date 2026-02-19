//
//  FirestoreService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Entries Management
    
    func saveEntry(_ entry: Entry, for userId: String) async throws {
        let data: [String: Any] = [
            "date": Timestamp(date: entry.date),
            "mood": entry.mood.rawValue,
            "originalText": entry.originalText,
            "reformulatedText": entry.reformulatedText ?? "",
            "empathyText": entry.empathyText ?? "",
            "nextStep": entry.nextStep ?? "",
            "updatedAt": Timestamp(date: entry.updatedAt),
            "userId": userId
        ]
        
        try await db.collection("users")
            .document(userId)
            .collection("entries")
            .document(entry.id.uuidString)
            .setData(data, merge: true)
    }
    
    /// ページング用：指定件数だけ取得し、続きがあれば lastDoc を返す
    func loadEntriesPage(
        for userId: String,
        limit: Int = 30,
        startAfter: DocumentSnapshot? = nil
    ) async throws -> (entries: [Entry], lastDoc: DocumentSnapshot?) {
        var query: Query = db.collection("users")
            .document(userId)
            .collection("entries")
            .order(by: "date", descending: true)
            .limit(to: limit)

        if let startAfter = startAfter {
            query = query.start(afterDocument: startAfter)
        }

        let snapshot = try await query.getDocuments()

        let entries: [Entry] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            let id = UUID(uuidString: doc.documentID) ?? (data["id"] as? String).flatMap { UUID(uuidString: $0) }
            guard let id = id,
                  let timestamp = data["date"] as? Timestamp,
                  let moodRawValue = data["mood"] as? Int,
                  let mood = Mood(rawValue: moodRawValue),
                  let originalText = data["originalText"] as? String else {
                return nil
            }
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? timestamp.dateValue()
            return Entry(
                id: id,
                date: timestamp.dateValue(),
                mood: mood,
                originalText: originalText,
                reformulatedText: data["reformulatedText"] as? String,
                empathyText: data["empathyText"] as? String,
                nextStep: data["nextStep"] as? String,
                updatedAt: updatedAt
            )
        }

        return (entries, snapshot.documents.last)
    }

    /// 原則禁止。全件 read のため課金が増える。一覧は loadEntriesPage でページングすること。
    func loadAllEntries(for userId: String) async throws -> [Entry] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("entries")
            .order(by: "date", descending: true)
            .getDocuments()

        var entries: [Entry] = []
        for document in snapshot.documents {
            let data = document.data()
            let id = UUID(uuidString: document.documentID) ?? (data["id"] as? String).flatMap { UUID(uuidString: $0) }
            guard let id = id,
                  let timestamp = data["date"] as? Timestamp,
                  let moodRawValue = data["mood"] as? Int,
                  let mood = Mood(rawValue: moodRawValue),
                  let originalText = data["originalText"] as? String else {
                continue
            }
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? timestamp.dateValue()
            entries.append(Entry(
                id: id,
                date: timestamp.dateValue(),
                mood: mood,
                originalText: originalText,
                reformulatedText: data["reformulatedText"] as? String,
                empathyText: data["empathyText"] as? String,
                nextStep: data["nextStep"] as? String,
                updatedAt: updatedAt
            ))
        }
        return entries
    }
    
    func deleteEntry(_ entryId: UUID, for userId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("entries")
            .document(entryId.uuidString)
            .delete()
    }
    
    func deleteAllEntries(for userId: String) async throws {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("entries")
            .getDocuments()
        
        let batch = db.batch()
        
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
    }
    
    // MARK: - Data Migration
    
    func migrateLocalData(_ entries: [Entry], for userId: String) async throws {
        let batch = db.batch()
        
        for entry in entries {
            let data: [String: Any] = [
                "date": Timestamp(date: entry.date),
                "mood": entry.mood.rawValue,
                "originalText": entry.originalText,
                "reformulatedText": entry.reformulatedText ?? "",
                "empathyText": entry.empathyText ?? "",
                "nextStep": entry.nextStep ?? "",
                "updatedAt": Timestamp(date: entry.updatedAt),
                "userId": userId
            ]
            
            let ref = db.collection("users")
                .document(userId)
                .collection("entries")
                .document(entry.id.uuidString)
            
            batch.setData(data, forDocument: ref)
        }
        
        try await batch.commit()
    }
}

