import Foundation
import SwiftUI

/// Configurações do app, persistidas em UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("startAtLogin") var startAtLogin = false
    @AppStorage("speakResponses") var speakResponses = true
    @AppStorage("pushToTalk") var pushToTalk = false
    @AppStorage("hotkeyOptionSpace") var hotkeyOptionSpace = true
    @AppStorage("temperature") var temperature = 0.7
    @AppStorage("maxTokens") var maxTokens = 1024
    @AppStorage("ttsSpeed") var ttsSpeed = 1.0
    @AppStorage("language") var language = "pt"
    @AppStorage("keepAudio") var keepAudio = false
}
