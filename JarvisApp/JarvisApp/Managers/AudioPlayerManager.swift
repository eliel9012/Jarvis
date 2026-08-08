import AVFoundation
import Foundation

enum TemporaryAudioFiles {
    static func remove(_ url: URL) {
        guard url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Reproduz o áudio de resposta com controles de stop/repeat/volume.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentURL: URL?
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var streamEngine: AVAudioEngine?
    private var streamPlayer: AVAudioPlayerNode?
    private var streamFormat: AVAudioFormat?
    private var pendingStreamBuffers = 0
    private var streamEnded = false
    private var streamDrainContinuation: CheckedContinuation<Void, Never>?

    func play(url: URL) async throws {
        stop()
        try Task.checkCancellation()

        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = volume
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        currentURL = url
        isPlaying = true

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                playbackContinuation = continuation
                if !player.play() {
                    finishPlayback()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        try Task.checkCancellation()
    }

    func play(
        stream: AsyncThrowingStream<TTSStreamEvent, Error>,
        onPlaybackStarted: @MainActor () -> Void
    ) async throws {
        stop()
        try Task.checkCancellation()
        streamEnded = false
        var receivedAudio = false

        do {
            try await withTaskCancellationHandler {
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .ready(_):
                        continue
                    case .audio(let sampleRate, let pcm):
                        guard !pcm.isEmpty else { continue }
                        try schedulePCM(pcm, sampleRate: sampleRate)
                        if !receivedAudio {
                            receivedAudio = true
                            try startStreamPlayback()
                            onPlaybackStarted()
                        }
                    case .done(_, _, _):
                        continue
                    }
                }
                guard receivedAudio else {
                    throw BackendError.invalidStream("TTS não gerou áudio")
                }
                streamEnded = true
                await waitForStreamDrain()
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            }
            try Task.checkCancellation()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        player?.stop()
        player = nil
        streamPlayer?.stop()
        streamEngine?.stop()
        streamPlayer = nil
        streamEngine = nil
        streamFormat = nil
        pendingStreamBuffers = 0
        streamEnded = true
        currentURL = nil
        isPlaying = false
        playbackContinuation?.resume()
        playbackContinuation = nil
        streamDrainContinuation?.resume()
        streamDrainContinuation = nil
    }

    func replay() {
        guard let currentURL else { return }
        Task { try? await play(url: currentURL) }
    }

    private func finishPlayback() {
        player = nil
        currentURL = nil
        isPlaying = false
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    private func schedulePCM(_ data: Data, sampleRate: Double) throws {
        if streamEngine == nil {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw BackendError.invalidStream("Formato de áudio inválido")
            }
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            streamEngine = engine
            streamPlayer = node
            streamFormat = format
        }

        guard let node = streamPlayer, let format = streamFormat,
              abs(format.sampleRate - sampleRate) < 1 else {
            throw BackendError.invalidStream("Taxa de amostragem mudou durante a fala")
        }
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let channel = buffer.floatChannelData?[0] else {
            throw BackendError.invalidStream("Bloco PCM vazio")
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<frameCount {
                channel[index] = Float(Int16(littleEndian: samples[index])) / 32768.0
            }
        }
        pendingStreamBuffers += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                self?.streamBufferFinished()
            }
        }
    }

    private func startStreamPlayback() throws {
        guard let engine = streamEngine, let node = streamPlayer else {
            throw BackendError.invalidStream("Player de streaming indisponível")
        }
        try engine.start()
        node.play()
        isPlaying = true
    }

    private func streamBufferFinished() {
        pendingStreamBuffers = max(0, pendingStreamBuffers - 1)
        if streamEnded && pendingStreamBuffers == 0 {
            finishStreamPlayback()
        }
    }

    private func waitForStreamDrain() async {
        if pendingStreamBuffers == 0 {
            finishStreamPlayback()
            return
        }
        await withCheckedContinuation { continuation in
            streamDrainContinuation = continuation
            if pendingStreamBuffers == 0 {
                finishStreamPlayback()
            }
        }
    }

    private func finishStreamPlayback() {
        streamPlayer?.stop()
        streamEngine?.stop()
        streamPlayer = nil
        streamEngine = nil
        streamFormat = nil
        pendingStreamBuffers = 0
        isPlaying = false
        streamDrainContinuation?.resume()
        streamDrainContinuation = nil
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finishPlayback()
        }
    }
}
