//
//  DraftSession.swift
//  GokigenNote
//
//  編集中の1件。id はセッション開始時（言い換え/記録の初回）に1回だけ発行し、同 doc に upsert する。
//

import Foundation

enum AutoSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

struct DraftSession: Equatable {
    var id: String
    var rawText: String = ""
    var rewriteText: String = ""
    var empathyText: String = ""
    var scene: String = ""
    var inputMethod: String = "text"
    var moodRaw: String = ""
    var nextStep: String = ""
    var createdAtLocal: Date = .now
    var autoSaveState: AutoSaveState = .idle

    var hasContent: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !rewriteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !empathyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
