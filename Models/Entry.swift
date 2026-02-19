//
//  Untitled.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/19.
//
import Foundation

struct Entry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var mood: Mood
    var originalText: String
    var reformulatedText: String? // 言語化されたテキスト
    var empathyText: String?
    var nextStep: String?
    /// 更新日時。保存/編集/AI反映のたびに更新。過去データは date でフォールバック。
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mood: Mood,
        originalText: String,
        reformulatedText: String? = nil,
        empathyText: String? = nil,
        nextStep: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.mood = mood
        self.originalText = originalText
        self.reformulatedText = reformulatedText
        self.empathyText = empathyText
        self.nextStep = nextStep
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, date, mood, originalText, reformulatedText, empathyText, nextStep, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        mood = try c.decode(Mood.self, forKey: .mood)
        originalText = try c.decode(String.self, forKey: .originalText)
        reformulatedText = try c.decodeIfPresent(String.self, forKey: .reformulatedText)
        empathyText = try c.decodeIfPresent(String.self, forKey: .empathyText)
        nextStep = try c.decodeIfPresent(String.self, forKey: .nextStep)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(mood, forKey: .mood)
        try c.encode(originalText, forKey: .originalText)
        try c.encode(reformulatedText, forKey: .reformulatedText)
        try c.encode(empathyText, forKey: .empathyText)
        try c.encode(nextStep, forKey: .nextStep)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
