//
//  SpeechInputService.swift
//  GokigenNote
//
//  音声入力 → テキスト変換。言い換え・言語化の入口。
//

import Foundation
import Combine
import Speech
import AVFoundation

/// 音声認識の状態
enum SpeechInputState: Equatable {
    case idle
    case authorized
    case denied
    case restricted
    case notDetermined
    case recording
    case processing
    case transcribing  // 停止後・テキスト確定中（UX用）
    case completed     // 正常完了（UX用）
    case error(String)
}

@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var state: SpeechInputState = .idle
    @Published private(set) var recognizedText: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private let locale: Locale

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 権限を要求し、状態を更新する
    func requestAuthorization() async {
        let auth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        switch auth {
        case .authorized:
            state = .authorized
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .notDetermined
        @unknown default:
            state = .notDetermined
        }
    }

    /// 現在の権限状態を取得（起動時など）
    func checkAuthorization() async {
        await requestAuthorization()
    }

    /// 録音開始。認識結果は `recognizedText` に逐次入る。完了後に `stopRecording()` で確定。
    func startRecording() async {
        guard state != .recording else { return }
        guard speechRecognizer != nil, speechRecognizer!.isAvailable else {
            state = .error("音声認識を利用できません")
            return
        }
        if state == .denied || state == .restricted {
            return
        }
        if state != .authorized && state != .recording && state != .processing && state != .transcribing && state != .completed {
            await requestAuthorization()
            if state != .authorized { return }
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("マイクを利用できません")
            reset()
            return
        }
        #endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            state = .error("マイクの開始に失敗しました")
            reset()
            return
        }

        state = .recording
        recognizedText = ""

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, err in
            Task { @MainActor in
                if let result, result.isFinal {
                    self?.recognizedText = result.bestTranscription.formattedString
                } else if result != nil {
                    self?.recognizedText = result!.bestTranscription.formattedString
                }
                if let err {
                    if err._code != 216 /* cancelled */ {
                        self?.state = .error(err.localizedDescription)
                        self?.reset()
                    }
                }
            }
        }
    }

    /// 録音停止。この時点の `recognizedText` を確定として返す
    func stopRecording() async -> String {
        state = .transcribing
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        let text = recognizedText
        let hadError: Bool = {
            if case .error = state { return true }
            return false
        }()
        reset()
        state = hadError ? state : .completed
        return text
    }

    private func reset() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
    }

    /// 権限が取れていて利用可能か
    var canRecord: Bool {
        switch state {
        case .authorized, .idle, .completed: return speechRecognizer?.isAvailable ?? false
        case .recording, .processing, .transcribing: return true
        default: return false
        }
    }
}
