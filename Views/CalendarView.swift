//
//  CalendarView.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import SwiftUI

struct CalendarView: View {
    @ObservedObject var vm: GokigenViewModel
    @State private var selectedDate: Date = Date()
    @State private var selectedEntry: Entry?
    @State private var showEntryDetail = false
    
    private let calendar = Calendar.current
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // カレンダーヘッダー
                    monthHeader
                    
                    // 曜日ヘッダー
                    weekdayHeader
                    
                    // カレンダーグリッド
                    calendarGrid
                    
                    // 選択された日付の記録
                    if let entries = entriesForSelectedDate(), !entries.isEmpty {
                        selectedDateSection(entries: entries)
                    } else {
                        emptyDateSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("カレンダー")
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
            }
        }
    }
    
    // MARK: - Month Header
    
    private var monthHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            
            Spacer()
            
            Text(monthYearString)
                .font(.title2.bold())
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Weekday Header
    
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { day in
                Text(day)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        let days = generateDaysInMonth()
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        hasEntry: hasEntry(for: date),
                        mood: getMood(for: date),
                        textLengthLevel: getTextLengthLevel(for: date)
                    )
                    .onTapGesture {
                        selectedDate = date
                    }
                } else {
                    Color.clear
                        .frame(height: 50)
                }
            }
        }
    }
    
    // MARK: - Selected Date Section
    
    private func selectedDateSection(entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDateString)
                .font(.headline)
            
            ForEach(entries) { entry in
                Button(action: { selectedEntry = entry }) {
                    HStack {
                        Text(entry.mood.emoji)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.originalText)
                                .font(.body)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var emptyDateSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("この日の記録はありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Helper Functions
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: selectedDate)
    }
    
    private var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)の記録"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: selectedDate)
    }
    
    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func generateDaysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var days: [Date?] = []
        var currentDate = monthFirstWeek.start
        
        while days.count < 42 { // 6週間分
            if calendar.isDate(currentDate, equalTo: selectedDate, toGranularity: .month) {
                days.append(currentDate)
            } else {
                days.append(nil)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func hasEntry(for date: Date) -> Bool {
        vm.entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
    }
    
    private func getMood(for date: Date) -> Mood? {
        vm.entries.first { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }?.mood
    }
    
    private func entriesForSelectedDate() -> [Entry]? {
        let entries = vm.entries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: selectedDate)
        }
        return entries.isEmpty ? nil : entries
    }
    
    // 文字数に応じた色の濃さレベル（0-5）を取得
    private func getTextLengthLevel(for date: Date) -> Int {
        let entries = vm.entries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
        
        guard !entries.isEmpty else { return 0 }
        
        // その日の最大文字数を取得
        let maxLength = entries.map { $0.originalText.count }.max() ?? 0
        
        // 文字数に応じて5段階にレベル分け
        switch maxLength {
        case 0:
            return 0
        case 1...30:
            return 1  // 最も薄い
        case 31...60:
            return 2  // 薄い
        case 61...90:
            return 3  // 中間
        case 91...150:
            return 4  // 濃い
        default:
            return 5  // 最も濃い（150文字以上）
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasEntry: Bool
    let mood: Mood?
    let textLengthLevel: Int // 0-5のレベル
    
    private let calendar = Calendar.current
    
    // 文字数レベルに応じた色の濃さを取得
    private var backgroundOpacity: Double {
        switch textLengthLevel {
        case 0: return 0.0      // 記録なし
        case 1: return 0.15     // 1-30文字: 最も薄い
        case 2: return 0.30     // 31-60文字: 薄い
        case 3: return 0.50     // 61-90文字: 中間
        case 4: return 0.70     // 91-150文字: 濃い
        case 5: return 0.90     // 150文字以上: 最も濃い
        default: return 0.0
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.body)
                .foregroundStyle(textLengthLevel >= 4 ? .white : .primary)
            
            if let mood = mood {
                Text(mood.emoji)
                    .font(.caption2)
            } else if hasEntry {
                Circle()
                    .fill(textLengthLevel >= 4 ? Color.white : Color.blue)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
    }
}

