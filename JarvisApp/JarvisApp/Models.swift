import Foundation
import SwiftUI

enum JarvisState: Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case synthesizing
    case speaking
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Ocioso"
        case .listening: return "Ouvindo..."
        case .transcribing: return "Transcrevendo..."
        case .thinking: return "Pensando..."
        case .synthesizing: return "Gerando voz..."
        case .speaking: return "Falando..."
        case .error(let message): return "Erro: \(message)"
        }
    }

    var detail: String {
        switch self {
        case .idle: return "Pronto quando você estiver"
        case .listening: return "Fale naturalmente"
        case .transcribing: return "Convertendo sua voz em texto"
        case .thinking: return "Criando uma resposta"
        case .synthesizing: return "Preparando a voz"
        case .speaking: return "Respondendo"
        case .error: return "Tente novamente"
        }
    }
}

enum MessageSource: String, Codable {
    case typed
    case stt
    case assistant
}

extension BackendManager.Status {
    var label: String {
        switch self {
        case .connecting: return "Conectando..."
        case .online: return "Online"
        case .offline: return "Offline"
        }
    }

    var color: Color {
        switch self {
        case .connecting: return .yellow
        case .online: return .green
        case .offline: return .red
        }
    }
}

enum ConversationHistory {
    /// Espelha `llm.context_compaction_threshold` de Config/config.json — o limite real
    /// de contexto usado pelo Qwen local, não uma contagem arbitrária de mensagens.
    static let defaultTokenBudget = 28_000

    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Mantém as mensagens mais recentes que cabem no orçamento de tokens do modelo,
    /// permitindo retomar conversas antigas sem estourar o contexto.
    static func trimmed(_ history: [ChatMessage], tokenBudget: Int = defaultTokenBudget) -> [ChatMessage] {
        guard !history.isEmpty else { return history }
        var total = 0
        var kept: [ChatMessage] = []
        for message in history.reversed() {
            let cost = estimateTokens(message.content)
            if !kept.isEmpty && total + cost > tokenBudget {
                break
            }
            total += cost
            kept.append(message)
        }
        return kept.reversed()
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var source: MessageSource

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        source: MessageSource = .typed
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.source = source
    }
}

struct ConversationResponse: Codable {
    let transcript: String
    let response: String
    let reasoning: String?
    let audio_path: String
    let audio_duration_s: Double?
    let latency_s: Double?
    let llm_latency_s: Double?
    let tts_rtf: Double?
    let stt_processing_s: Double?
}

struct ChatResponse: Codable {
    let content: String
    let reasoning: String?
    let latency_s: Double?
    let usage: Usage?

    struct Usage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

struct HealthResponse: Codable {
    let status: String
    let local: Bool
    let llm: LLMStatus?
    let stt: ModelStatus?
    let tts: ModelStatus?

    struct LLMStatus: Codable {
        let online: Bool
        let base_url: String
    }
    struct ModelStatus: Codable {
        let model: String
        let loaded: Bool
    }
}

struct ModelsResponse: Codable {
    let llm: LLMModels?
    let stt: String?
    let tts: TTSModels?

    struct LLMModels: Codable {
        let model: String
        let available: [String]
    }
    struct TTSModels: Codable {
        let model: String
        let language: String
    }
}

struct STTResponse: Codable {
    let text: String
    let language: String
    let duration: Double
    let processing_time: Double
    let rtf: Double?
}

struct TTSResponse: Codable {
    let text: String
    let audio_path: String
    let audio_duration_s: Double?
    let total_s: Double?
    let rtf: Double?
}

enum TTSStreamEvent {
    case ready(sampleRate: Double)
    case audio(sampleRate: Double, pcmS16LE: Data)
    case done(audioDuration: Double?, total: Double?, rtf: Double?)
}
