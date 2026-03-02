//
//  LineCheckRecord.swift
//  GokigenNote
//
//  地雷ストッパー履歴。users/{uid}/lineChecks/{checkId} のスキーマ。
//

import Foundation
import FirebaseFirestore

enum LineRisk: String, Codable, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
}

struct LineSuggestion: Codable, Hashable {
    let label: String
    let text: String
}

struct QueueInfo: Codable {
    var tier: String?
    var waitedMs: Int?
}

struct LineCheckRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var createdAt: Timestamp?
    var inputText: String?
    var risk: LineRisk
    var riskScore: Int?
    var oneLiner: String
    var suggestions: [LineSuggestion]?
    var selectedLabel: String?
    var copiedIndex: Int?
    var sentFeedback: String?
    var planAtTime: String?
    var latencyMs: Int?
    var queue: QueueInfo?

    var createdDate: Date {
        createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
    }
}
