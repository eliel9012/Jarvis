@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// Controla o microfone via AVFoundation: captura 16 kHz mono, fornece nível
/// para waveform e roda transcrição ao vivo (só exibição) via Speech on-device
/// enquanto grava. O áudio final ainda vai pro Whisper local no backend —
/// a transcrição ao vivo aqui é só feedback visual, não a fonte da verdade.
/// O VAD local encerra automaticamente depois que detecta fala seguida de silêncio.
@MainActor
final class MicrophoneManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published private(set) var levels: [Float] = []
    @Published private(set) var liveTranscript = ""

    var onSilenceDetected: (() -> Void)?

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioNode?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    private var outputFileURL: URL?
    private var isStopping = false
    private var recordingStartedAt = Date()
    private var lastVoiceActivity = Date()
    private var voiceCandidateStartedAt: Date?
    private var hasDetectedSpeech = false
    private var silenceCallbackSent = false
    private let voiceThreshold: Float = 0.12
    private let voiceActivationDuration: TimeInterval = 0.25
    private let silenceDuration: TimeInterval = 0.8
    private let minimumRecordingDuration: TimeInterval = 2.5

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Permissão separada do Speech framework, só usada pra transcrição ao vivo (exibição).
    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isStopping = false
        liveTranscript = ""
        levels = []
        level = 0
        recordingStartedAt = Date()
        lastVoiceActivity = recordingStartedAt
        voiceCandidateStartedAt = nil
        hasDetectedSpeech = false
        silenceCallbackSent = false
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let hwFormat = input.outputFormat(forBus: 0)

            converter = AVAudioConverter(from: hwFormat, to: outputFormat)
            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent("jarvis_capture_\(UUID().uuidString).wav")
            audioFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
            outputFileURL = url

            startLiveTranscription(format: hwFormat)

            input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                Task { @MainActor [weak self] in
                    self?.process(buffer: buffer)
                }
            }
            inputNode = input
            engine.prepare()
            try engine.start()
            self.engine = engine
            isRecording = true
        } catch {
            _ = stopRecording()
            print("[Microphone] erro ao iniciar: \(error)")
        }
    }

    private func startLiveTranscription(format: AVAudioFormat) {
        guard let speechRecognizer, speechRecognizer.isAvailable,
              speechRecognizer.supportsOnDeviceRecognition else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                self?.liveTranscript = text
            }
        }
    }

    func stopRecording() -> URL? {
        guard !isStopping else { return outputFileURL }
        isStopping = true
        isRecording = false
        inputNode?.removeTap(onBus: 0)
        engine?.stop()
        engine?.reset()
        engine = nil
        inputNode = nil
        converter = nil
        audioFile = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        return outputFileURL
    }

    private func process(buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)

        guard let converter else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else { return }
        var error: NSError?
        nonisolated(unsafe) let sourceBuffer = buffer
        nonisolated(unsafe) var inputProvided = false
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            guard !inputProvided else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard status != .error, converted.frameLength > 0 else { return }

        guard let samples = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            let s = samples[i]
            sum += s * s
        }
        let rms = (sum / Float(count)).squareRoot()
        let norm = min(max(rms * 5.0, 0), 1)
        level = norm
        levels.append(norm)
        if levels.count > 60 { levels.removeFirst(levels.count - 60) }

        let now = Date()
        if norm >= voiceThreshold {
            if hasDetectedSpeech {
                lastVoiceActivity = now
            } else {
                let candidateStart = voiceCandidateStartedAt ?? now
                voiceCandidateStartedAt = candidateStart
                if now.timeIntervalSince(candidateStart) >= voiceActivationDuration {
                    hasDetectedSpeech = true
                    lastVoiceActivity = now
                }
            }
        } else {
            voiceCandidateStartedAt = nil
            if hasDetectedSpeech,
               !silenceCallbackSent,
               now.timeIntervalSince(recordingStartedAt) >= minimumRecordingDuration,
               now.timeIntervalSince(lastVoiceActivity) >= silenceDuration {
                silenceCallbackSent = true
                onSilenceDetected?()
            }
        }

        try? audioFile?.write(from: converted)
    }
}
