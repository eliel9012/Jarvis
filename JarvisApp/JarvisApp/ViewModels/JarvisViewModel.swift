import Foundation
import SwiftUI

/// Orquestra a conversa: microfone → STT → LLM → TTS → reprodução.
@MainActor
final class JarvisViewModel: ObservableObject {
    @Published var state: JarvisState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var backendOnline = false
    @Published var footerModels = "Qwen 3.6 35B • Fish S2 Pro • Whisper Turbo"

    let settings = AppSettings()
    let microphone = MicrophoneManager()
    let audioPlayer = AudioPlayerManager()
    let backendManager = BackendManager()
    let models = ModelManager()
    let client = BackendClient.shared

    private var history: [ChatMessage] = []

    func start() {
        backendManager.startMonitoring()
        Task {
            backendOnline = await backendManager.isBackendHealthy()
            if let config = try? JSONSerialization.jsonObject(
                with: Data(contentsOf: configURL)
            ) as? [String: Any], let llm = config["llm"] as? [String: Any] {
                let q = llm["quality_model"] as? String ?? "Qwen"
                footerModels = "\(q) • Fish S2 Pro • Whisper Turbo"
            }
        }
    }

    private var configURL: URL {
        let base = NSString(string: "~/Developer/Jarvis").expandingTildeInPath
        return URL(fileURLWithPath: base).appendingPathComponent("Config/config.json")
    }

    // MARK: - Listening

    func startListening() {
        guard backendOnline else {
            state = .error("Backend offline")
            return
        }
        Task {
            let granted = await microphone.requestPermission()
            guard granted else {
                state = .error("Permissão de microfone negada")
                return
            }
            state = .listening
            microphone.startRecording { [weak self] in
                self?.processCapture()
            }
        }
    }

    func stopListening() {
        guard state == .listening else { return }
        processCapture()
    }

    func stopEverything() {
        audioPlayer.stop()
        _ = microphone.stopRecording()
        if state != .idle { state = .idle }
    }

    // MARK: - Pipeline de voz

    private func processCapture() {
        guard let url = microphone.stopRecording() else { return }
        Task {
            state = .transcribing
            do {
                let result = try await client.conversation(
                    file: url,
                    mode: settings.llmMode.rawValue,
                    speed: settings.ttsSpeed
                )
                let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else {
                    state = .idle
                    return
                }
                appendMessage(role: "user", content: transcript)
                let answer = result.response
                appendMessage(role: "assistant", content: answer)
                state = .speaking
                if settings.speakResponses {
                    let audioURL = URL(fileURLWithPath: result.audio_path)
                    audioPlayer.play(url: audioURL)
                }
                if state == .speaking {
                    state = .idle
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Texto

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard backendOnline else {
            state = .error("Backend offline")
            return
        }
        appendMessage(role: "user", content: trimmed)
        Task {
            state = .thinking
            do {
                let result = try await client.chat(
                    messages: history + [ChatMessage(role: "user", content: trimmed)],
                    maxTokens: settings.maxTokens
                )
                let answer = result.content.isEmpty ? (result.reasoning ?? "") : result.content
                appendMessage(role: "assistant", content: answer)
                if settings.speakResponses {
                    state = .speaking
                    let tts = try await client.tts(
                        text: answer,
                        model: settings.ttsModelRaw == "fast" ? "mlx-community/fish-audio-s2-pro-8bit" : "mlx-community/fish-audio-s2-pro-bf16",
                        speed: settings.ttsSpeed,
                        refAudio: settings.refVoiceEnabled && !settings.refAudioPath.isEmpty ? settings.refAudioPath : nil,
                        refText: settings.refVoiceEnabled && !settings.refTranscript.isEmpty ? settings.refTranscript : nil
                    )
                    audioPlayer.play(url: URL(fileURLWithPath: tts.audio_path))
                }
                if state != .idle { state = .idle }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func clearConversation() {
        messages = []
        history = []
        audioPlayer.stop()
        state = .idle
    }

    private func appendMessage(role: String, content: String) {
        let msg = ChatMessage(role: role, content: content)
        messages.append(msg)
        history.append(msg)
        history = LLMMode.trimmed(history)
    }

    func refreshBackendStatus() {
        Task {
            backendOnline = await backendManager.isBackendHealthy()
        }
    }
}
