import AppKit
import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var viewModel = JarvisViewModel()
    @StateObject private var hotkey = HotkeyManager()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .frame(minWidth: 520, minHeight: 640)
                .onAppear {
                    hotkey.onPushToTalk = {
                        if viewModel.settings.pushToTalk {
                            viewModel.startListening()
                        }
                    }
                    hotkey.onPushToTalkRelease = {
                        if viewModel.settings.pushToTalk, viewModel.state == .listening {
                            viewModel.stopListening()
                        }
                    }
                    hotkey.install()
                }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            Button("Abrir Jarvis") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Começar a Ouvir") {
                viewModel.startListening()
            }
            .disabled(!viewModel.canStartInteraction)
            Button("Interromper") {
                viewModel.stopEverything()
            }
            .disabled(!viewModel.canInterrupt)
            Divider()
            Text("Backend: \(viewModel.backendStatus.label)")
            Divider()
            Button("Sair") {
                viewModel.stopEverything()
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.state == .idle ? "circle.hexagongrid.fill" : "waveform")
        }

        Settings {
            SettingsView(settings: viewModel.settings, viewModel: viewModel)
        }
    }
}

/// Push-to-talk global: segura ⌥+Space para ouvir, solta para processar.
@MainActor
final class HotkeyManager: ObservableObject {
    var onPushToTalk: (() -> Void)?
    var onPushToTalkRelease: (() -> Void)?

    private var monitor: Any?
    private var isHeld = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.modifierFlags.contains(.option), event.keyCode == 49 else { return } // Space
        if event.type == .keyDown && !isHeld {
            isHeld = true
            onPushToTalk?()
        } else if event.type == .keyUp && isHeld {
            isHeld = false
            onPushToTalkRelease?()
        }
    }
}
