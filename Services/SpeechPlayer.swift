//
//  SpeechPlayer.swift
//  GokigenNote
//
//  言い換え結果の音声再生。聞ける = 行動できる。
//

import AVFoundation

final class SpeechPlayer {
    static let shared = SpeechPlayer()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
