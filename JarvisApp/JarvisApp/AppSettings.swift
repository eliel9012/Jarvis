import Foundation
import SwiftUI

/// Configurações do app, persistidas em UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("startAtLogin") var startAtLogin = false
    @AppStorage("speakResponses") var speakResponses = true
    @AppStorage("pushToTalk") var pushToTalk = false
    @AppStorage("hotkeyOptionSpace") var hotkeyOptionSpace = true
    @AppStorage("llmMode") var llmModeRaw = LLMMode.quality.rawValue
    @AppStorage("temperature") var temperature = 0.7
    @AppStorage("maxTokens") var maxTokens = 1024
    @AppStorage("contextSize") var contextSize = 70000
    @AppStorage("ttsModel") var ttsModelRaw = "quality"
    @AppStorage("ttsSpeed") var ttsSpeed = 1.0
    @AppStorage("refVoiceEnabled") var refVoiceEnabled = false
    @AppStorage("refAudioPath") var refAudioPath = ""
    @AppStorage("refTranscript") var refTranscript = ""
    @AppStorage("language") var language = "pt"
    @AppStorage("vadThreshold") var vadThreshold = 0.02
    @AppStorage("keepAudio") var keepAudio = false

    var llmMode: LLMMode {
        get { LLMMode(rawValue: llmModeRaw) ?? .quality }
        set { llmModeRaw = newValue.rawValue }
    }
}
