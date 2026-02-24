//
//  FirestoreService.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

/// 新スキーマ用。音声ファイルは入れない（P0 はテキストのみ）。将来 audio 拡張用の余地あり。
struct EntryPayload {
    var entryId: String?   // クライアント生成の固定ID（docIdとして使用・冪等用）
    var dateKey: String?   // "yyyy-MM-dd" クライアント生成（表示・集計用、タイムゾーンずれ防止）
    var scene: String
    var inputMethod: String  // "voice" | "text"
    var rawText: String
    var rewriteText: String?
    var empathyText: String?
    var moodRaw: String?
    var nextStep: String?
    var promptMeta: [String: Any]?
    var model: String?
    var usage: [String: Any]?
    var client: [String: Any]?  // 端末情報のみ（platform / appVersion 等）
}

final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    private init() {}

    // MARK: - User Document（UID を主キーにした初回作成・idempotent）

    /// サインイン直後に1回だけ呼ぶ。既にドキュメントがあれば何もしない。
    func ensureUserDoc(uid: String, email: String?, displayName: String?) async throws {
        let ref = db.collection("users").document(uid)
        var data: [String: Any] = [
            "createdAt": FieldValue.serverTimestamp(),
            "version": 1
        ]
        if let email = email { data["email"] = email }
        if let displayName = displayName { data["displayName"] = displayName }

        try await db.runTransaction { (transaction, errorPointer) -> Any? in
            do {
                let snap = try transaction.getDocument(ref)
                if snap.exists { return nil }
                transaction.setData(data, forDocument: ref)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    // MARK: - Entries Management

    /// 同一 doc に upsert。createdAt は初回のみ、updatedAt は毎回。isFinalized は false で上書き。
    func upsertEntry(uid: String, entryId: String, payload: EntryPayload) async throws {
        let ref = db.collection("users").document(uid).collection("entries").document(entryId)
        try await db.runTransaction { (txn, errorPointer) -> Any? in
            do {
                let snap = try txn.getDocument(ref)
                let exists = snap.exists
                let alreadyFinalized = (snap.data()?["isFinalized"] as? Bool) ?? false

                var data: [String: Any] = [
                    "scene": payload.scene,
                    "inputMethod": payload.inputMethod,
                    "rawText": payload.rawText,
                    "rewriteText": payload.rewriteText ?? "",
                    "empathyText": payload.empathyText ?? "",
                    "updatedAt": FieldValue.serverTimestamp(),
                    "isFinalized": alreadyFinalized ? true : false
                ]
                if let dk = payload.dateKey { data["dateKey"] = dk }
                if !exists {
                    data["date"] = FieldValue.serverTimestamp()
                    data["createdAt"] = FieldValue.serverTimestamp()
                }
                if let mood = payload.moodRaw { data["mood"] = mood }
                if let next = payload.nextStep { data["nextStep"] = next }
                if let m = payload.promptMeta { data["promptMeta"] = m }
                if let m = payload.model { data["model"] = m }
                if let u = payload.usage { data["usage"] = u }
                if let c = payload.client { data["client"] = c }

                txn.setData(data, forDocument: ref, merge: true)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
    }

    /// 確定フラグを立てる（idempotent）。存在しない doc はエラー。
    func finalizeEntry(uid: String, entryId: String) async throws {
        let ref = db.collection("users").document(uid).collection("entries").document(entryId)

        try await db.runTransaction { (txn, errorPointer) -> Any? in
            do {
                let snap = try txn.getDocument(ref)
                guard snap.exists else {
                    throw NSError(
                        domain: "FirestoreService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "finalize failed: entry does not exist (\(entryId))"]
                    )
                }

                let alreadyFinalized = (snap.data()?["isFinalized"] as? Bool) ?? false
                if alreadyFinalized {
                    // idempotent: 何も変えない（finalizedAt を揺らさない）
                    return nil
                }

                txn.setData([
                    "isFinalized": true,
                    "finalizedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: ref, merge: true)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
    }

    /// 新スキーマで1件作成。entryId 指定で upsert（冪等）。createdAt は初回のみ、updatedAt は毎回。
    func createEntry(uid: String, payload: EntryPayload) async throws -> String {
        let entryId = payload.entryId ?? UUID().uuidString
        let ref = db.collection("users").document(uid).collection("entries").document(entryId)

        var data: [String: Any] = [
            "scene": payload.scene,
            "inputMethod": payload.inputMethod,
            "rawText": payload.rawText,
            "rewriteText": payload.rewriteText ?? "",
            "empathyText": payload.empathyText ?? "",
            "date": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let dk = payload.dateKey { data["dateKey"] = dk }
        if let mood = payload.moodRaw { data["mood"] = mood }
        if let next = payload.nextStep { data["nextStep"] = next }
        if let m = payload.promptMeta { data["promptMeta"] = m }
        if let m = payload.model { data["model"] = m }
        if let u = payload.usage { data["usage"] = u }
        if let c = payload.client { data["client"] = c }

        try await db.runTransaction { (tx, errorPointer) -> Any? in
            do {
                let snap = try tx.getDocument(ref)
                if snap.exists, snap.data()?["createdAt"] != nil {
                    tx.setData(data, forDocument: ref, merge: true)
                } else {
                    var firstData = data
                    firstData["createdAt"] = FieldValue.serverTimestamp()
                    tx.setData(firstData, forDocument: ref, merge: true)
                }
            } catch {
                var firstData = data
                firstData["createdAt"] = FieldValue.serverTimestamp()
                tx.setData(firstData, forDocument: ref, merge: true)
            }
            return nil
        }
        return entryId
    }

    /// 既存エントリを部分更新。updatedAt は必ず serverTimestamp で上書き。
    func updateEntry(uid: String, entryId: String, patch: [String: Any]) async throws {
        let ref = db.collection("users").document(uid).collection("entries").document(entryId)
        var p = patch
        p["updatedAt"] = FieldValue.serverTimestamp()
        try await ref.updateData(p)
    }
    
    /// 旧 Entry を新スキーマに寄せて createEntry で upsert（互換ラッパー）。
    func saveEntry(_ entry: Entry, for userId: String) async throws {
        let payload = EntryPayload(
            entryId: entry.documentId ?? entry.id.uuidString,
            dateKey: Self.dayKey(from: entry.date),
            scene: "unknown",
            inputMethod: "text",
            rawText: entry.originalText,
            rewriteText: entry.reformulatedText,
            empathyText: entry.empathyText,
            moodRaw: String(entry.mood.rawValue),
            nextStep: entry.nextStep,
            promptMeta: nil,
            model: nil,
            usage: nil,
            client: ["platform": "iOS"]
        )
        _ = try await createEntry(uid: userId, payload: payload)
    }

    static func dayKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.string(from: date)
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
            let docId = doc.documentID
            if let rawText = data["rawText"] as? String {
                let dateTs = (data["date"] as? Timestamp) ?? (data["createdAt"] as? Timestamp) ?? (data["updatedAt"] as? Timestamp)
                let date = dateTs?.dateValue() ?? Date()
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? date
                return Entry(
                    id: UUID(uuidString: docId) ?? UUID(),
                    documentId: docId,
                    date: date,
                    mood: .neutral,
                    originalText: rawText,
                    reformulatedText: data["rewriteText"] as? String,
                    empathyText: data["empathyText"] as? String,
                    nextStep: nil,
                    updatedAt: updatedAt
                )
            }
            guard let timestamp = data["date"] as? Timestamp,
                  let moodRawValue = data["mood"] as? Int,
                  let mood = Mood(rawValue: moodRawValue),
                  let originalText = data["originalText"] as? String else {
                return nil
            }
            let id = UUID(uuidString: docId) ?? (data["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? timestamp.dateValue()
            return Entry(
                id: id,
                documentId: docId,
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
            let docId = document.documentID
            if let rawText = data["rawText"] as? String {
                let dateTs = (data["date"] as? Timestamp) ?? (data["createdAt"] as? Timestamp) ?? (data["updatedAt"] as? Timestamp)
                let date = dateTs?.dateValue() ?? Date()
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? date
                entries.append(Entry(
                    id: UUID(uuidString: docId) ?? UUID(),
                    documentId: docId,
                    date: date,
                    mood: .neutral,
                    originalText: rawText,
                    reformulatedText: data["rewriteText"] as? String,
                    empathyText: data["empathyText"] as? String,
                    nextStep: nil,
                    updatedAt: updatedAt
                ))
                continue
            }
            guard let timestamp = data["date"] as? Timestamp,
                  let moodRawValue = data["mood"] as? Int,
                  let mood = Mood(rawValue: moodRawValue),
                  let originalText = data["originalText"] as? String else {
                continue
            }
            let id = UUID(uuidString: docId) ?? (data["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? timestamp.dateValue()
            entries.append(Entry(
                id: id,
                documentId: docId,
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

    /// documentID 指定で削除（新スキーマの auto ID 用）
    func deleteEntry(entryId: String, for userId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("entries")
            .document(entryId)
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

