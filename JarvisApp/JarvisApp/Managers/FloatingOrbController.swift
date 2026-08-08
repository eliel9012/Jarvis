import AppKit
import SwiftUI

/// Alterna entre janela completa e um orbe compacto sempre acima dos outros apps.
@MainActor
final class FloatingOrbController: ObservableObject {
    @Published private(set) var isFloating = false

    private let viewModel: JarvisViewModel
    private weak var mainWindow: NSWindow?
    private var panel: NSPanel?

    init(viewModel: JarvisViewModel) {
        self.viewModel = viewModel
    }

    func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.backgroundColor = NSColor(
            red: 0.015,
            green: 0.035,
            blue: 0.065,
            alpha: 1
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    func toggle() {
        isFloating ? restoreMainWindow() : showFloatingOrb()
    }

    func showFloatingOrb() {
        let panel = panel ?? makePanel()
        self.panel = panel
        mainWindow?.orderOut(nil)
        positionIfNeeded(panel)
        panel.orderFrontRegardless()
        isFloating = true
    }

    func restoreMainWindow() {
        panel?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        isFloating = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(
            rootView: FloatingOrbPanelView(
                viewModel: viewModel,
                onRestore: { [weak self] in self?.restoreMainWindow() }
            )
        )
        return panel
    }

    private func positionIfNeeded(_ panel: NSPanel) {
        guard !panel.isVisible, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.midY - panel.frame.height / 2
            )
        )
    }
}

private struct FloatingOrbPanelView: View {
    @ObservedObject var viewModel: JarvisViewModel
    let onRestore: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().fill(JarvisTheme.background.opacity(0.72))
                }
                .overlay {
                    Circle().stroke(JarvisTheme.border.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: JarvisTheme.cyan.opacity(0.28), radius: 24)

            Button(action: toggleListening) {
                OrbView(state: viewModel.state, size: 106)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state != .listening && !viewModel.canStartInteraction && !viewModel.canInterrupt)
            .help(viewModel.state == .listening ? "Parar e processar" : "Falar com Jarvis")

            Button(action: onRestore) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(JarvisTheme.backgroundRaised, in: Circle())
                    .overlay { Circle().stroke(JarvisTheme.border.opacity(0.7), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .help("Abrir janela completa")
        }
        .padding(8)
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jarvis flutuante, estado: \(viewModel.state.label)")
    }

    private func toggleListening() {
        if viewModel.state == .listening {
            viewModel.stopListening()
        } else if viewModel.canStartInteraction {
            viewModel.startListening()
        } else if viewModel.canInterrupt {
            viewModel.stopEverything()
        }
    }
}

struct WindowAttachment: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowProbeView {
        WindowProbeView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {}
}

final class WindowProbeView: NSView {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    init(onWindowAvailable: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in onWindowAvailable(window) }
    }
}
