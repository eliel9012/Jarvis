import SwiftUI

/// Settings nativo do macOS.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: JarvisViewModel
    @State private var selectedTab = SettingsTab.general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case llm = "LLM"
        case voice = "Voice"
        case speech = "Speech Recognition"
        case privacy = "Privacy"
        case advanced = "Advanced"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            LLMTab(settings: settings)
                .tabItem { Label("LLM", systemImage: "brain.head.profile") }
                .tag(SettingsTab.llm)
            VoiceTab(settings: settings)
                .tabItem { Label("Voice", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.voice)
            SpeechTab(settings: settings)
                .tabItem { Label("Speech", systemImage: "waveform") }
                .tag(SettingsTab.speech)
            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)
            AdvancedTab(viewModel: viewModel)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
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
                Text("Start at Login")
            }
            Toggle("Speak responses", isOn: $settings.speakResponses)
            Toggle("Push-to-talk shortcut (⌥ Space)", isOn: $settings.pushToTalk)
        }
        .formStyle(.grouped)
    }
}

private struct LLMTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Picker("Mode", selection: $settings.llmModeRaw) {
                Text("Quality").tag(LLMMode.quality.rawValue)
                Text("Fast").tag(LLMMode.fast.rawValue)
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Quality") { Text("Qwen 3.6 35B A3B") }
            LabeledContent("Fast") { Text("Qwen 3.5 9B") }
            Slider(value: $settings.temperature, in: 0.0...1.5, step: 0.05) {
                Text("Temperature: \(String(format: "%.2f", settings.temperature))")
            }
            Stepper("Max tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 128...8192, step: 128)
            Stepper("Context size: \(settings.contextSize)", value: $settings.contextSize, in: 8192...200000, step: 1024)
        }
        .formStyle(.grouped)
    }
}

private struct VoiceTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Picker("Voice model", selection: $settings.ttsModelRaw) {
                Text("Fish S2 Pro BF16").tag("quality")
                Text("Fish S2 Pro 8-bit").tag("fast")
            }
            .pickerStyle(.radioGroup)
            Slider(value: $settings.ttsSpeed, in: 0.5...2.0, step: 0.05) {
                Text("Speaking speed: \(String(format: "%.2f", settings.ttsSpeed))x")
            }
            Toggle("Reference Voice", isOn: $settings.refVoiceEnabled)
            if settings.refVoiceEnabled {
                TextField("Reference audio path", text: $settings.refAudioPath)
                TextField("Reference transcript", text: $settings.refTranscript)
                Text("Salve o áudio de referência em ~/Developer/Jarvis/Audio/references/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SpeechTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            LabeledContent("Model") { Text("Whisper Large v3 Turbo") }
            Picker("Language", selection: $settings.language) {
                Text("Auto").tag("auto")
                Text("pt-BR").tag("pt")
            }
            Slider(value: $settings.vadThreshold, in: 0.005...0.15, step: 0.005) {
                Text("VAD threshold: \(String(format: "%.3f", settings.vadThreshold))")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    @AppStorage("keepAudio") private var keepAudio = false
    var body: some View {
        Form {
            LabeledContent("Local processing") { Text("ON").foregroundStyle(.green).bold() }
            LabeledContent("Network requests") { Text("OFF").foregroundStyle(.red).bold() }
            Toggle("Keep audio recordings", isOn: $keepAudio)
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
            LabeledContent("Backend status") {
                Text(viewModel.backendStatus.label)
                    .foregroundStyle(viewModel.backendStatus.color)
            }
            LabeledContent("Backend") { Text("127.0.0.1:8765") }
            Button("Restart service") {
                viewModel.refreshBackendStatus()
            }
            Button("View logs") {
                let url = URL(fileURLWithPath: NSString(string: "~/Developer/Jarvis/Logs/backend.out.log").expandingTildeInPath)
                NSWorkspace.shared.open(url)
            }
            Button("Model status") {
                viewModel.models.refresh()
            }
            List(viewModel.models.models) { m in
                HStack {
                    Circle().fill(m.installed ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(m.name).font(.caption)
                    Spacer()
                    Text(m.installed ? ByteCountFormatter.string(fromByteCount: m.sizeBytes, countStyle: .file) : "missing")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 160)
        }
        .formStyle(.grouped)
    }
}
