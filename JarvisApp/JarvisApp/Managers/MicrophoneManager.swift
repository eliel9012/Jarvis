import AVFoundation
import Foundation

/// Controla o microfone via AVFoundation: captura 16 kHz mono,
/// fornece nível para waveform e faz VAD por RMS (600 ms de silêncio).
@MainActor
final class MicrophoneManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published private(set) var levels: [Float] = []

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioNode?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    private var silenceSamples: Int64 = 0
    private let autoStopEnabled = true
    private let silenceSamplesForStop: Int64 = 9600 // 600 ms a 16 kHz
    private var outputFileURL: URL?
    private var isStopping = false
    private var onAutoStop: (() -> Void)?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording(onAutoStop: (() -> Void)? = nil) {
        guard !isRecording else { return }
        self.onAutoStop = onAutoStop
        isStopping = false
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let hwFormat = input.outputFormat(forBus: 0)
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hwFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else { return }

            converter = AVAudioConverter(from: hwFormat, to: outputFormat)
            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent("jarvis_capture_\(UUID().uuidString).wav")
            audioFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
            outputFileURL = url

            input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                Task { @MainActor [weak self] in
                    self?.process(buffer: buffer, monoFormat: monoFormat)
                }
            }
            inputNode = input
            engine.prepare()
            try engine.start()
            self.engine = engine
            isRecording = true
            silenceSamples = 0
        } catch {
            stopRecording()
            print("[Microphone] erro ao iniciar: \(error)")
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
        onAutoStop = nil
        return outputFileURL
    }

    private func process(buffer: AVAudioPCMBuffer, monoFormat: AVAudioFormat) {
        guard let converter else { return }
        var converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(buffer.frameLength * 2))!
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
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

        try? audioFile?.write(from: converted)

        if rms < 0.02 {
            silenceSamples += Int64(count)
        } else {
            silenceSamples = 0
        }
        if autoStopEnabled, silenceSamples >= silenceSamplesForStop, isRecording {
            let cb = onAutoStop
            _ = stopRecording()
            cb?()
        }
    }
}
