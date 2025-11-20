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
    var empathyText: String?
    var nextStep: String?
}
