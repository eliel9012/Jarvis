import SwiftUI

/// Experiência principal do Jarvis, baseada na referência visual escolhida.
struct MainView: View {
    @ObservedObject var viewModel: JarvisViewModel
    @ObservedObject var floatingController: FloatingOrbController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @State private var textInput = ""
    @State private var isShowingLaunch = true
    @State private var isShowingHistory = false

    var body: some View {
        ZStack {
            JarvisBackground()

            mainContent
                .opacity(isShowingLaunch ? 0 : 1)
                .scaleEffect(isShowingLaunch && !reduceMotion ? 0.985 : 1)

            if isShowingLaunch {
                LaunchSequenceView {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.35)) {
                        isShowingLaunch = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingHistory) {
            HistoryPanelView(historyStore: viewModel.historyStore)
        }
        .task {
            if viewModel.messages.isEmpty {
                viewModel.start()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                let orbSize = min(410, max(285, geometry.size.height * 0.49))
                VStack(spacing: 0) {
                    hero(orbSize: orbSize)
                        .frame(maxHeight: .infinity)

                    ConversationView(messages: viewModel.messages)
                        .frame(height: min(160, max(125, geometry.size.height * 0.20)))
                        .padding(.horizontal, 78)

                    composer
                        .padding(.horizontal, 78)

                    Label("Processamento local", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(JarvisTheme.secondaryText)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Jarvis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(JarvisTheme.primaryText)
                .padding(.leading, 74)
                .frame(width: 220, alignment: .leading)

            Rectangle()
                .fill(JarvisTheme.border.opacity(0.22))
                .frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(viewModel.backendStatus.color)
                        .frame(width: 9, height: 9)
                    Text(viewModel.backendStatus == .online ? "Local · online" : "Local · \(viewModel.backendStatus.label.lowercased())")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(JarvisTheme.primaryText)
                }
                Text(viewModel.footerModels.replacingOccurrences(of: " pt-BR", with: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(JarvisTheme.secondaryText)
            }
            .padding(.leading, 22)

            Spacer()

            HStack(spacing: 12) {
                JarvisGlassEffectGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        JarvisIconButton(systemName: "clock.arrow.circlepath", help: "Histórico") {
                            isShowingHistory = true
                        }
                        JarvisIconButton(systemName: "gearshape", help: "Ajustes") {
                            openSettings()
                        }
                        JarvisIconButton(systemName: "pip.enter", help: "Modo orbe flutuante") {
                            floatingController.showFloatingOrb()
                        }
                    }
                }
            }
            .padding(.trailing, 22)
        }
        .frame(height: 66)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JarvisTheme.border.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func hero(orbSize: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack {
                WaveformView(
                    levels: viewModel.microphone.levels,
                    isActive: viewModel.state == .listening
                )
                .frame(maxWidth: 980)

                OrbView(state: viewModel.state, size: orbSize * 1.5)
            }
            .frame(height: orbSize * 0.91)

            Text(viewModel.state.label)
                .id(viewModel.state.label)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(JarvisTheme.primaryText)
                .transition(.move(edge: .bottom).combined(with: .opacity))

            Text(viewModel.state.detail)
                .font(.system(size: 16))
                .foregroundStyle(JarvisTheme.secondaryText)

            ActivityTicks(state: viewModel.state)
                .padding(.top, 6)
        }
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42), value: viewModel.state.label)
    }

    private var composer: some View {
        JarvisGlassEffectGroup(spacing: 14) {
            HStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(JarvisTheme.cyan)
                    .frame(width: 42, height: 42)

                TextField("Pergunte ao Jarvis...", text: $textInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(JarvisTheme.primaryText)
                    .disabled(!viewModel.canStartInteraction)
                    .onSubmit(sendText)

                Text("⌥ Espaço para falar")
                    .font(.system(size: 13))
                    .foregroundStyle(JarvisTheme.secondaryText)

                Button(action: toggleListening) {
                    Image(systemName: viewModel.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .jarvisGlassButton(
                    tint: viewModel.state == .listening
                        ? Color.red.opacity(0.72)
                        : JarvisTheme.cyan.opacity(0.68),
                    prominent: true
                )
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel(viewModel.state == .listening ? "Parar e processar" : "Falar com Jarvis")
                .disabled(viewModel.state != .listening && !viewModel.canStartInteraction)
            }
            .padding(.horizontal, 18)
            .frame(height: 72)
            .jarvisGlassSurface(
                tint: JarvisTheme.cyan.opacity(viewModel.state == .listening ? 0.12 : 0.055),
                interactive: true,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .shadow(color: JarvisTheme.cyan.opacity(0.10), radius: 28, y: 10)
        }
        .animation(.snappy(duration: 0.35), value: viewModel.state == .listening)
    }

    private func sendText() {
        viewModel.sendText(textInput)
        textInput = ""
    }

    private func toggleListening() {
        if viewModel.state == .listening {
            viewModel.stopListening()
        } else {
            viewModel.startListening()
        }
    }
}

private struct ActivityTicks: View {
    let state: JarvisState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<13, id: \.self) { index in
                    let phase = sin(time * 4.5 + Double(index) * 0.78)
                    Capsule()
                        .fill(JarvisTheme.cyan.opacity(state == .idle ? 0.36 : 0.85))
                        .frame(width: 3, height: state == .idle ? 4 : 5 + abs(phase) * 15)
                }
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

private struct HistoryPanelView: View {
    let historyStore: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [ConversationRecord] = []

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "Sem histórico",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Suas conversas locais aparecerão aqui.")
                    )
                } else {
                    List(conversations) { conversation in
                        DisclosureGroup {
                            ForEach(historyStore.messages(for: conversation)) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == "user" ? "Você" : "Jarvis")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(message.role == "user" ? .secondary : JarvisTheme.cyan)
                                    Text(message.text)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conversation.title)
                                Text(conversation.createdAt, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Histórico")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .frame(width: 620, height: 520)
        .task { conversations = historyStore.allConversations() }
    }
}
