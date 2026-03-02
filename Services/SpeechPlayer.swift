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

    /// 音声は受話口（イヤピース）に出す。外に漏れないようにする（TestFlight フィードバック対応）。
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

