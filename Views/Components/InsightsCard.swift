//
//  InsightsCard.swift
//  GokigenNote
//
//  傾向（直近）の軽量表示。
//

import SwiftUI

struct InsightsCard: View {
    let insights: LineInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("傾向（直近）")
                .font(.headline)

            HStack {
                stat("LOW", insights.low)
                stat("MED", insights.medium)
                stat("HIGH", insights.high)
            }

            Text("コピー率: \(Int(insights.copyRate * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !insights.topTriggers.isEmpty {
                Text("よく出るパターン")
                    .font(.subheadline.weight(.semibold))
                ForEach(insights.topTriggers.indices, id: \.self) { i in
                    let item = insights.topTriggers[i]
                    Text("・\(item.0)（\(item.1)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !insights.bestTimeSlots.isEmpty {
                Text("多い時間帯")
                    .font(.subheadline.weight(.semibold))
                Text(insights.bestTimeSlots.map { "\($0.0)" }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
