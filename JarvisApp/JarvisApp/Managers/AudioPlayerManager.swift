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

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        playbackContinuation?.resume()
        playbackContinuation = nil
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
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finishPlayback()
        }
    }
}
