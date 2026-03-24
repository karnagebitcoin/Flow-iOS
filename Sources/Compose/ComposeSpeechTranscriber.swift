import AVFoundation
import Foundation
import Speech

@MainActor
final class ComposeSpeechTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var elapsedMs: Int = 0

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var tickerTask: Task<Void, Never>?

    private var latestTranscript = ""
    private var onTranscriptionComplete: ((String) -> Void)?
    private var startedAt: Date?

    deinit {
        tickerTask?.cancel()
        recognitionTask?.cancel()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggleRecording(onTranscript: @escaping (String) -> Void) async -> String? {
        if isRecording {
            stopRecording()
            return nil
        }

        if isTranscribing {
            return nil
        }

        do {
            try await startRecording(onTranscript: onTranscript)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Could not start voice input."
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        isTranscribing = true
        stopTicker()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func startRecording(onTranscript: @escaping (String) -> Void) async throws {
        let speechAuthorization = await requestSpeechAuthorization()
        guard speechAuthorization == .authorized else {
            throw SpeechInputError.speechPermissionDenied
        }

        let hasMicrophonePermission = await requestMicrophonePermission()
        guard hasMicrophonePermission else {
            throw SpeechInputError.microphonePermissionDenied
        }

        cleanupRecognition()

        let locale = Locale.autoupdatingCurrent
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        speechRecognizer = recognizer
        latestTranscript = ""
        elapsedMs = 0
        startedAt = Date()
        onTranscriptionComplete = onTranscript

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setPreferredSampleRate(44_100)
        try audioSession.setPreferredInputNumberOfChannels(1)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        guard let format = preferredRecordingFormat(for: inputNode) else {
            throw SpeechInputError.microphoneUnavailable
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishTranscription()
                        return
                    }
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                        self.finishTranscription()
                        return
                    }
                    self.finishTranscription()
                }
            }
        }

        isRecording = true
        isTranscribing = false
        startTicker()
    }

    private func finishTranscription() {
        guard isRecording || isTranscribing else { return }

        isRecording = false
        isTranscribing = false
        stopTicker()
        cleanupRecognition()

        let transcript = latestTranscript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        latestTranscript = ""

        if !transcript.isEmpty {
            onTranscriptionComplete?(transcript)
        }
        onTranscriptionComplete = nil
    }

    private func cleanupRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        audioEngine.inputNode.removeTap(onBus: 0)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func preferredRecordingFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let inputFormat = inputNode.inputFormat(forBus: 0)
        if isUsableRecordingFormat(inputFormat) {
            return inputFormat
        }

        let outputFormat = inputNode.outputFormat(forBus: 0)
        if isUsableRecordingFormat(outputFormat) {
            return outputFormat
        }

        return nil
    }

    private func isUsableRecordingFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func startTicker() {
        stopTicker()

        tickerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isRecording {
                if let startedAt {
                    self.elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

enum SpeechInputError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission is blocked."
        case .microphonePermissionDenied:
            return "Microphone permission is blocked."
        case .recognizerUnavailable:
            return "Voice input isn't available right now."
        case .microphoneUnavailable:
            return "Microphone input isn't available right now."
        }
    }
}
