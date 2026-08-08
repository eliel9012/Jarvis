import Foundation
import WhisperKit

// WhisperKit não anota Sendable, mas só é usado aqui dentro de uma classe @MainActor
// (nunca de fato acessado por duas threads ao mesmo tempo).
extension WhisperKit: @retroactive @unchecked Sendable {}

/// STT nativo em Swift via WhisperKit (on-device, Core ML). Substitui o
/// Whisper que rodava no backend Python — essa é agora a fonte da verdade
/// da transcrição enviada ao LLM (a transcrição ao vivo do MicrophoneManager
/// continua sendo só feedback visual via Speech framework da Apple).
///
/// Modelo baixa uma vez (Hugging Face, ~mesmo tier do whisper-large-v3-turbo
/// que rodava no Python) e fica cacheado localmente — depois disso é 100% local.
@MainActor
final class WhisperTranscriber {
    private var pipe: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?

    private func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        if let loadTask {
            let result = try await loadTask.value
            pipe = result
            return result
        }
        let task = Task<WhisperKit, Error> {
            try await WhisperKit(WhisperKitConfig(model: "large-v3-v20240930_turbo"))
        }
        loadTask = task
        let result = try await task.value
        pipe = result
        loadTask = nil
        return result
    }

    /// Pré-carrega o modelo em background assim que o app inicia, pra não
    /// pagar o custo de download/carregamento na primeira fala do usuário.
    func preload() {
        guard pipe == nil, loadTask == nil else { return }
        Task { _ = try? await loadedPipe() }
    }

    /// `language` nil deixa o Whisper detectar automaticamente.
    func transcribe(audioPath: String, language: String?) async throws -> String {
        let pipe = try await loadedPipe()
        let options = DecodingOptions(language: language, detectLanguage: language == nil)
        let results = try await pipe.transcribe(audioPath: audioPath, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
