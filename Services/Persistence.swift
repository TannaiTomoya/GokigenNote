//
//  Untitled.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation

final class Persistence {
    static let shared = Persistence()
    private init() {}

    private let key = "entries_v1"

    func save(_ entries: [Entry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Save error:", error)
        }
    }

    func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            print("Load error:", error)
            return []
        }
    }
}
