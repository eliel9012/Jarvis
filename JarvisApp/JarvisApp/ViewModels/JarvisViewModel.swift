import Combine
import Foundation
import SwiftUI

/// Orquestra a conversa: microfone → STT → LLM → TTS → reprodução.
@MainActor
final class JarvisViewModel: ObservableObject {
    @Published var state: JarvisState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var backendStatus: BackendManager.Status = .connecting
    @Published var footerModels = "Qwen 3.5 9B • Qwen3-TTS pt-BR • Whisper Turbo"

    var backendOnline: Bool { backendStatus == .online }
    var canStartInteraction: Bool {
        guard backendOnline else { return false }
        if state == .idle { return true }
        if case .error = state { return true }
        return false
    }
    var canInterrupt: Bool {
        state != .idle && !isErrorState
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }

    let settings = AppSettings()
    let microphone = MicrophoneManager()
    let audioPlayer = AudioPlayerManager()
    let backendManager = BackendManager()
    let models = ModelManager()
    let historyStore = HistoryStore()
    let client = BackendClient.shared

    private var history: [ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()
    private var responseTask: Task<Void, Never>?

    func start() {
        backendManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.backendStatus, on: self)
            .store(in: &cancellables)
        backendManager.startMonitoring()
        microphone.onSilenceDetected = { [weak self] in
            self?.stopListening()
        }
        Task {
            if let config = try? JSONSerialization.jsonObject(
                with: Data(contentsOf: configURL)
            ) as? [String: Any],
               let llm = config["llm"] as? [String: Any] {
                let q = llm["model"] as? String ?? "Qwen 3.5 9B"
                footerModels = "\(q) • Qwen3-TTS 1.7B pt-BR • Whisper Turbo"
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
        guard canStartInteraction else { return }
        Task {
            let granted = await microphone.requestPermission()
            guard granted else {
                state = .error("Permissão de microfone negada")
                return
            }
            // Transcrição ao vivo é só um extra visual — sem essa permissão, segue sem ela.
            let liveTranscriptionEnabled = await microphone.requestSpeechPermission()
            state = .listening
            microphone.startRecording(enableLiveTranscription: liveTranscriptionEnabled)
        }
    }

    func stopListening() {
        guard state == .listening else { return }
        processCapture()
    }

    func stopEverything() {
        responseTask?.cancel()
        responseTask = nil
        audioPlayer.stop()
        _ = microphone.stopRecording()
        if state != .idle { state = .idle }
    }

    // MARK: - Pipeline de voz

    /// O WAV fica neste Mac e é transcrito pelo Whisper MLX no backend local.
    private func processCapture() {
        guard let url = microphone.stopRecording() else { return }
        responseTask?.cancel()
        responseTask = Task {
            defer { responseTask = nil }
            state = .transcribing
            do {
                let transcript = try await client.stt(file: url).text
                guard !transcript.isEmpty else {
                    state = .idle
                    return
                }
                await respond(to: transcript)
            } catch is CancellationError {
                state = .idle
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
        guard canStartInteraction else { return }
        responseTask?.cancel()
        responseTask = Task {
            await respond(to: trimmed)
            responseTask = nil
        }
    }

    /// LLM (`/chat`) + TTS (`/tts`) — compartilhado entre voz e texto.
    private func respond(to userText: String) async {
        appendMessage(role: "user", content: userText)
        state = .thinking
        do {
            try Task.checkCancellation()
            let result = try await client.chat(
                messages: history,
                maxTokens: settings.maxTokens,
                temperature: settings.temperature
            )
            let answer = result.content.isEmpty ? (result.reasoning ?? "") : result.content
            appendMessage(role: "assistant", content: answer)
            if settings.speakResponses {
                state = .synthesizing
                let tts = try await client.tts(
                    text: answer,
                    speed: settings.ttsSpeed
                )
                try Task.checkCancellation()
                state = .speaking
                try await audioPlayer.play(url: URL(fileURLWithPath: tts.audio_path))
            }
            if state != .idle { state = .idle }
        } catch is CancellationError {
            state = .idle
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
        history = ConversationHistory.trimmed(history)
        historyStore.append(role: role, text: content)
    }

    func refreshBackendStatus() {
        Task {
            await backendManager.checkNow()
        }
    }
}
