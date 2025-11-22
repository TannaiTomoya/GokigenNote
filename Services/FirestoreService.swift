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
            "id": entry.id.uuidString,
            "date": Timestamp(date: entry.date),
            "mood": entry.mood.rawValue,
            "originalText": entry.originalText,
            "reformulatedText": entry.reformulatedText ?? "",
            "empathyText": entry.empathyText ?? "",
            "nextStep": entry.nextStep ?? "",
            "userId": userId
        ]
        
        try await db.collection("users")
            .document(userId)
            .collection("entries")
            .document(entry.id.uuidString)
            .setData(data)
    }
    
    func loadEntries(for userId: String) async throws -> [Entry] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("entries")
            .order(by: "date", descending: true)
            .getDocuments()
        
        var entries: [Entry] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let timestamp = data["date"] as? Timestamp,
                  let moodRawValue = data["mood"] as? Int,
                  let mood = Mood(rawValue: moodRawValue),
                  let originalText = data["originalText"] as? String else {
                continue
            }
            
            let entry = Entry(
                id: id,
                date: timestamp.dateValue(),
                mood: mood,
                originalText: originalText,
                reformulatedText: data["reformulatedText"] as? String,
                empathyText: data["empathyText"] as? String,
                nextStep: data["nextStep"] as? String
            )
            
            entries.append(entry)
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
                "id": entry.id.uuidString,
                "date": Timestamp(date: entry.date),
                "mood": entry.mood.rawValue,
                "originalText": entry.originalText,
                "reformulatedText": entry.reformulatedText ?? "",
                "empathyText": entry.empathyText ?? "",
                "nextStep": entry.nextStep ?? "",
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

