//
//  TriggerExtractor.swift
//  GokigenNote
//
//  傾向分析用。oneLiner から「地雷パターン」を軽量抽出。
//

import Foundation

enum TriggerExtractor {
    static func extract(from oneLiner: String) -> [String] {
        let t = oneLiner
        var out: [String] = []

        func has(_ s: String) -> Bool { t.contains(s) }

        if has("既読") || has("未読") { out.append("既読/未読") }
        if has("なんで") || has("どうして") { out.append("詰問") }
        if has("返信") || has("返事") || has("いつ") { out.append("追いLINE") }
        if has("最悪") || has("無理") || has("嫌い") { out.append("攻撃ワード") }

        return out.isEmpty ? ["不明"] : out
    }
}

enum TimeSlotter {
    static func slot(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 0...5: return "深夜"
        case 6...11: return "午前"
        case 12...17: return "午後"
        default: return "夜"
        }
    }
}
