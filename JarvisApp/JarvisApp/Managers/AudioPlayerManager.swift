import AVFoundation
import Foundation

/// Reproduz o áudio de resposta com controles de stop/repeat/volume.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentURL: URL?
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?

    func play(url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.delegate = self
            player.play()
            self.player = player
            currentURL = url
            isPlaying = true
        } catch {
            print("[AudioPlayer] erro: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
    }

    func replay() {
        guard let currentURL else { return }
        play(url: currentURL)
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
