//
//  Entry Detail View.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//
import SwiftUI

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("気分") {
                    Text(entry.mood.emoji)
                        .font(.system(size: 56))
                        .accessibilityLabel(entry.mood.label)
                }
                Section("日付") {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                Section("本文") {
                    Text(entry.originalText.isEmpty ? "本文はありません。" : entry.originalText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let reformulated = entry.reformulatedText, !reformulated.isEmpty {
                    Section("言い換え") {
                        Text(reformulated)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let empathy = entry.empathyText, !empathy.isEmpty {
                    Section("やさしい言い換え") {
                        Text(empathy)
                    }
                }
                if let next = entry.nextStep, !next.isEmpty {
                    Section("次の一歩") {
                        Text(next)
                    }
                }
            }
            .navigationTitle("記録の詳細")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
    }
}
