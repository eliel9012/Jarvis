import SwiftUI

/// Settings nativo do macOS.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: JarvisViewModel
    @State private var selectedTab = SettingsTab.general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "Geral"
        case llm = "LLM"
        case voice = "Voz"
        case speech = "Reconhecimento de Fala"
        case privacy = "Privacidade"
        case advanced = "Avançado"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings)
                .tabItem { Label("Geral", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            LLMTab(settings: settings)
                .tabItem { Label("LLM", systemImage: "brain.head.profile") }
                .tag(SettingsTab.llm)
            VoiceTab(settings: settings)
                .tabItem { Label("Voz", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.voice)
            SpeechTab(settings: settings)
                .tabItem { Label("Fala", systemImage: "waveform") }
                .tag(SettingsTab.speech)
            PrivacyTab()
                .tabItem { Label("Privacidade", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)
            AdvancedTab(viewModel: viewModel)
                .tabItem { Label("Avançado", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
        }
        .frame(width: 540, height: 420)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Toggle(isOn: Binding(
                get: { settings.startAtLogin },
                set: { newValue in
                    settings.startAtLogin = newValue
                    LaunchAtLogin.setEnabled(newValue)
                }
            )) {
                Text("Iniciar no login")
            }
            Toggle("Falar respostas", isOn: $settings.speakResponses)
            Toggle("Atalho push-to-talk (⌥ Space)", isOn: $settings.pushToTalk)
        }
        .formStyle(.grouped)
    }
}

private struct LLMTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            LabeledContent("Modelo") { Text("Qwen 3.5 9B") }
            Slider(value: $settings.temperature, in: 0.0...1.5, step: 0.05) {
                Text("Temperatura: \(String(format: "%.2f", settings.temperature))")
            }
            Stepper("Máx. tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 128...8192, step: 128)
        }
        .formStyle(.grouped)
    }
}

private struct VoiceTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            LabeledContent("Modelo") { Text("Qwen3-TTS 1.7B 8-bit") }
            LabeledContent("Idioma") { Text("Português do Brasil") }
            Slider(value: $settings.ttsSpeed, in: 0.5...2.0, step: 0.05) {
                Text("Velocidade de fala: \(String(format: "%.2f", settings.ttsSpeed))x")
            }
            Text("Voz masculina brasileira em registro barítono, com sotaque neutro e processamento totalmente local.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct SpeechTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            LabeledContent("Modelo") { Text("Whisper Large v3 Turbo") }
            Picker("Idioma", selection: $settings.language) {
                Text("Automático").tag("auto")
                Text("pt-BR").tag("pt")
            }
            Text("Transcrição ao vivo (exibida durante a fala) usa Speech on-device da Apple. A gravação enviada ao Jarvis usa sempre o Whisper local.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    @AppStorage("keepAudio") private var keepAudio = false
    var body: some View {
        Form {
            LabeledContent("Processamento local") { Text("LIGADO").foregroundStyle(.green).bold() }
            LabeledContent("Requisições de rede") { Text("DESLIGADO").foregroundStyle(.red).bold() }
            Toggle("Manter gravações de áudio", isOn: $keepAudio)
            Text("Todo o processamento ocorre neste Mac. Nenhum áudio sai do dispositivo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedTab: View {
    @ObservedObject var viewModel: JarvisViewModel
    var body: some View {
        Form {
            LabeledContent("Status do backend") {
                Text(viewModel.backendStatus.label)
                    .foregroundStyle(viewModel.backendStatus.color)
            }
            LabeledContent("Backend") { Text("127.0.0.1:8765") }
            Button("Verificar agora") {
                viewModel.refreshBackendStatus()
            }
            Button("Ver logs") {
                let url = URL(fileURLWithPath: NSString(string: "~/Developer/Jarvis/Logs/backend.out.log").expandingTildeInPath)
                NSWorkspace.shared.open(url)
            }
            Button("Status dos modelos") {
                viewModel.models.refresh()
            }
            List(viewModel.models.models) { m in
                HStack {
                    Circle().fill(m.installed ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(m.name).font(.caption)
                    Spacer()
                    Text(m.installed ? ByteCountFormatter.string(fromByteCount: m.sizeBytes, countStyle: .file) : "ausente")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 160)
        }
        .formStyle(.grouped)
    }
}
