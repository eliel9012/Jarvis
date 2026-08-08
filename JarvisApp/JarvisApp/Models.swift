import Foundation
import SwiftUI

enum JarvisState: Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error(let message): return "Error: \(message)"
        }
    }
}

extension BackendManager.Status {
    var label: String {
        switch self {
        case .connecting: return "Connecting..."
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

enum LLMMode: String, CaseIterable, Identifiable {
    case quality
    case fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quality: return "Quality"
        case .fast: return "Fast"
        }
    }

    /// Mantém apenas as N mensagens mais recentes (rollover de contexto).
    static func trimmed(_ history: [ChatMessage], maxCount: Int = 40) -> [ChatMessage] {
        guard history.count > maxCount else { return history }
        return Array(history.suffix(maxCount))
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var role: String
    var content: String
    var timestamp: Date

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
        let quality: String
        let fast: String
        let available: [String]
    }
    struct TTSModels: Codable {
        let quality: String
        let fast: String
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
