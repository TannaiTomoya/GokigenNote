//
//  HistoryViewModel.swift
//  GokigenNote
//
//  履歴一覧・傾向分析（クライアント側集計）。
//

import Foundation
import Combine
import FirebaseFirestore

struct LineInsights {
    var low = 0
    var medium = 0
    var high = 0
    var copyRate: Double = 0
    var topLabels: [(String, Int)] = []
    var topTriggers: [(String, Int)] = []
    var bestTimeSlots: [(String, Int)] = []
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [LineCheckRecord] = []
    @Published var insights = LineInsights()
    @Published var riskFilter: LineRisk? = nil
    @Published var days: Int = 30

    private var listener: ListenerRegistration?

    func start(uid: String) {
        listener?.remove()
        listener = LineCheckRepository.shared.listenLatest(uid: uid, limit: 200) { [weak self] items in
            Task { @MainActor in
                self?.records = items
                self?.recomputeInsights()
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func filtered() -> [LineCheckRecord] {
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return records.filter { r in
            r.createdDate >= fromDate && (riskFilter == nil || r.risk == riskFilter!)
        }
    }

    func recomputeInsights() {
        let items = filtered()
        var low = 0, med = 0, high = 0
        var copyCount = 0
        var labelCount: [String: Int] = [:]
        var triggerCount: [String: Int] = [:]
        var slotCount: [String: Int] = [:]

        for r in items {
            switch r.risk {
            case .low: low += 1
            case .medium: med += 1
            case .high: high += 1
            }
            if r.copiedIndex != nil { copyCount += 1 }
            if let label = r.selectedLabel { labelCount[label, default: 0] += 1 }

            let triggers = TriggerExtractor.extract(from: r.oneLiner)
            for t in triggers { triggerCount[t, default: 0] += 1 }

            let slot = TimeSlotter.slot(for: r.createdDate)
            slotCount[slot, default: 0] += 1
        }

        let topLabels = labelCount.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        let topTriggers = triggerCount.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        let bestSlots = slotCount.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }

        insights = LineInsights(
            low: low,
            medium: med,
            high: high,
            copyRate: items.isEmpty ? 0 : Double(copyCount) / Double(items.count),
            topLabels: Array(topLabels),
            topTriggers: Array(topTriggers),
            bestTimeSlots: Array(bestSlots)
        )
    }
}
