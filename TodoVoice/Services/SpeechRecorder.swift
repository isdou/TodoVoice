import AVFoundation
import Speech

@MainActor
final class SpeechRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case readyToConfirm
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var audioLevels: [CGFloat] = []

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var didReceiveFinalResult = false

    var isRecording: Bool { state == .recording }

    func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        return speechGranted && microphoneGranted
    }

    func startRecording() async {
        guard await requestPermissions() else {
            state = .failed("请在系统设置中允许麦克风和语音识别权限")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("语音识别服务暂时不可用")
            return
        }

        stopEngine(resetTranscript: true)
        audioLevels = []
        didReceiveFinalResult = false

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = self?.calculateLevel(buffer) ?? 0
                Task { @MainActor in
                    self?.appendLevel(level)
                }
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.didReceiveFinalResult = true
                        }
                    }
                    if let error {
                        self.handleRecognitionError(error as NSError)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
        } catch {
            stopEngine(resetTranscript: false)
            state = .failed("无法开始录音")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        state = .processing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()

        try? await Task.sleep(for: .milliseconds(800))

        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            state = .failed("没有识别到内容，请重试")
        } else {
            state = .readyToConfirm
        }
    }

    func cancelRecording() {
        stopEngine(resetTranscript: true)
        state = .idle
    }

    func confirmAndReset() {
        transcript = ""
        audioLevels = []
        didReceiveFinalResult = false
        state = .idle
    }

    func resetError() {
        if case .failed = state {
            transcript = ""
            audioLevels = []
            didReceiveFinalResult = false
            state = .idle
        }
    }

    private func handleRecognitionError(_ error: NSError) {
        // If user already asked to stop and we have text, don't override to failed
        if case .processing = state {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Will be finalized by stopRecording() after sleep; do nothing
                return
            }
        }

        // These are end-of-stream codes that simply mean recognition finished;
        // treat as success if we have any transcript.
        let endCodes: Set<Int> = [203, 216] // recognition timeout / cancel
        if endCodes.contains(error.code) {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                stopEngine(resetTranscript: false)
                state = .readyToConfirm
                return
            }
        }

        stopEngine(resetTranscript: false)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .failed("没有识别到内容，请重试")
        } else {
            state = .readyToConfirm
        }
    }

    private func calculateLevel(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.05 }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 0.000001))
        let normalized = max(0.05, min(1.0, CGFloat((db + 50) / 50)))
        return normalized
    }

    private func appendLevel(_ level: CGFloat) {
        audioLevels.append(level)
        if audioLevels.count > 30 {
            audioLevels.removeFirst(audioLevels.count - 30)
        }
    }

    private func stopEngine(resetTranscript: Bool) {
        if audioEngine.isRunning { audioEngine.stop() }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if resetTranscript {
            transcript = ""
            audioLevels = []
            didReceiveFinalResult = false
        }
    }
}
