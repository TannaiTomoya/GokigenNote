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
    @State private var showCopyToast = false
    @State private var shareItem: ShareItem?

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
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(reformulated)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 12) {
                                Button(action: { copyText(reformulated) }) {
                                    Label("コピー", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: { shareText(reformulated) }) {
                                    Label("共有", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } header: {
                        Text("言い換え")
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
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item.text])
        }
        .overlay(toastOverlay, alignment: .bottom)
    }
    
    private var toastOverlay: some View {
        VStack {
            Spacer()
            if showCopyToast {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("コピーしました")
                        .foregroundStyle(.primary)
                }
                .padding()
                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 60)
    }
    
    // MARK: - Helper Functions
    
    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation {
            showCopyToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyToast = false
            }
        }
    }
    
    private func shareText(_ text: String) {
        guard !text.isEmpty else { return }
        shareItem = ShareItem(text: text)
    }
}
