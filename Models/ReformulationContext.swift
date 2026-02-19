//
//  ReformulationContext.swift
//  GokigenNote
//
//  言い換えの「目的・相手・トーン」選択用。Firebase は使用しない。
//

import Foundation

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

/// 言い換え生成に渡すコンテキスト（目的・相手・トーン）
struct ReformulationContext {
    var purpose: ReformulationPurpose
    var audience: ReformulationAudience
    var tone: ReformulationTone

    static let `default` = ReformulationContext(
        purpose: .shareFeeling,
        audience: .colleague,
        tone: .soft
    )
}
