//
//  TrainingPersistence.swift
//  GokigenNote
//

import Foundation

final class TrainingPersistence {
    static let shared = TrainingPersistence()
    private init() {}

    private let key = "training_sessions_v1"

    func save(_ sessions: [TrainingSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> [TrainingSession] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TrainingSession].self, from: data) else {
            return []
        }
        return decoded
    }
}
