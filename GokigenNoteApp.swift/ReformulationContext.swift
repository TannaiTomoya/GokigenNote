//
//  ReformulationContext.swift
//  GokigenNote
//
//  言い換えの「目的・相手・トーン・場面」選択用。Firebase は使用しない。
//

import Foundation

/// 場面（仕事／恋愛／日常／学校）。最初に選ぶ → 話す → 整う → 使える
enum ReformulationScene: String, CaseIterable, Identifiable {
    case work
    case romance
    case daily
    case school

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .work: return "仕事"
        case .romance: return "恋愛"
        case .daily: return "日常"
        case .school: return "学校"
        }
    }
}

/// Step1: 何を伝えたいか
enum ReformulationPurpose: String, CaseIterable, Identifiable {
    case convey = "伝えたい"
    case decline = "断りたい"
    case apologize = "謝りたい"
    case consult = "相談したい"
    case request = "依頼したい"
    case shareFeeling = "気持ちを伝えたい"

    var id: String { rawValue }
}

/// Step2: 誰に向けてか
enum ReformulationAudience: String, CaseIterable, Identifiable {
    case boss = "上司"
    case colleague = "同僚"
    case friend = "友人"
    case partner = "恋人"
    case family = "家族"
    case stranger = "初対面"

    var id: String { rawValue }
}

/// Step3: どんなトーンか
enum ReformulationTone: String, CaseIterable, Identifiable {
    case polite = "丁寧"
    case soft = "柔らかい"
    case casual = "カジュアル"
    case clear = "はっきり"
    case gentle = "優しい"

    var id: String { rawValue }
}

/// 言い換え生成に渡すコンテキスト（目的・相手・トーン・場面・年額か）
struct ReformulationContext {
    var purpose: ReformulationPurpose
    var audience: ReformulationAudience
    var tone: ReformulationTone
    var scene: ReformulationScene
    /// 年額ユーザー向けにプロンプトを強化するか
    var isYearly: Bool = false

    static let `default` = ReformulationContext(
        purpose: .shareFeeling,
        audience: .colleague,
        tone: .soft,
        scene: .work
    )
}
