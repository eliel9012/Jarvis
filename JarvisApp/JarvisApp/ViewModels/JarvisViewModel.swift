import Combine
import Foundation
import SwiftUI

/// Orquestra a conversa: microfone → STT → LLM → TTS → reprodução.
@MainActor
final class JarvisViewModel: ObservableObject {
    @Published var state: JarvisState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var backendStatus: BackendManager.Status = .connecting
    @Published var footerModels = "Qwen 3.6 35B • Fish S2 Pro • Whisper Turbo"

    var backendOnline: Bool { backendStatus == .online }

    let settings = AppSettings()
    let microphone = MicrophoneManager()
    let audioPlayer = AudioPlayerManager()
    let backendManager = BackendManager()
    let models = ModelManager()
    let historyStore = HistoryStore()
    let client = BackendClient.shared
    let transcriber = WhisperTranscriber()

    private var history: [ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()

    func start() {
        backendManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.backendStatus, on: self)
            .store(in: &cancellables)
        backendManager.startMonitoring()
        transcriber.preload()
        Task {
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
            // Transcrição ao vivo é só um extra visual — sem essa permissão, segue sem ela.
            _ = await microphone.requestSpeechPermission()
            state = .listening
            microphone.startRecording()
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

    /// Transcrição roda local (WhisperKit) — só o texto final vai pro backend, sem upload de áudio.
    private func processCapture() {
        guard let url = microphone.stopRecording() else { return }
        Task {
            state = .transcribing
            do {
                let language = settings.language == "auto" ? nil : settings.language
                let transcript = try await transcriber.transcribe(audioPath: url.path, language: language)
                guard !transcript.isEmpty else {
                    state = .idle
                    return
                }
                await respond(to: transcript)
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
        Task {
            await respond(to: trimmed)
        }
    }

    /// LLM (`/chat`) + TTS (`/tts`) — compartilhado entre voz e texto.
    private func respond(to userText: String) async {
        appendMessage(role: "user", content: userText)
        state = .thinking
        do {
            let result = try await client.chat(
                messages: history,
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
        historyStore.append(role: role, text: content)
    }

    func refreshBackendStatus() {
        Task {
            await backendManager.checkNow()
        }
    }
}
