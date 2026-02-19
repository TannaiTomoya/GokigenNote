//
//  Persistence.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation

/// ユーザー別 entries キャッシュ（ローカル先出し・オフライン用）
protocol EntryCache: AnyObject {
    func loadEntries(userId: String) -> [Entry]
    func saveEntries(_ entries: [Entry], userId: String)
}

final class Persistence: EntryCache {
    static let shared = Persistence()
    private init() {}

    private let key = "entries_v1"
    private func key(for userId: String) -> String { "entries_v1_\(userId)" }
    private func pendingKey(for userId: String) -> String { "pending_entry_ids_\(userId)" }

    // MARK: - ユーザー別キャッシュ（EntryCache）

    func loadEntries(userId: String) -> [Entry] {
        let k = key(for: userId)
        guard let data = UserDefaults.standard.data(forKey: k),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveEntries(_ entries: [Entry], userId: String) {
        let k = key(for: userId)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: k)
    }

    // MARK: - 従来API（未ログイン／レガシー用）

    func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - 未同期キュー（Firestore 保存失敗時の再送用）

    func loadPendingEntryIds(userId: String) -> [UUID] {
        let k = pendingKey(for: userId)
        guard let data = UserDefaults.standard.data(forKey: k),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    func savePendingEntryIds(_ ids: [UUID], userId: String) {
        let k = pendingKey(for: userId)
        let strings = ids.map { $0.uuidString }
        guard let data = try? JSONEncoder().encode(strings) else { return }
        UserDefaults.standard.set(data, forKey: k)
    }

    func addPendingEntryId(_ id: UUID, userId: String) {
        var ids = loadPendingEntryIds(userId: userId)
        if !ids.contains(id) { ids.append(id) }
        savePendingEntryIds(ids, userId: userId)
    }

    func removePendingEntryId(_ id: UUID, userId: String) {
        let ids = loadPendingEntryIds(userId: userId).filter { $0 != id }
        savePendingEntryIds(ids, userId: userId)
    }
}
