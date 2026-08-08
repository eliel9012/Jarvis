import SwiftUI

/// Tela principal do Jarvis.
struct MainView: View {
    @ObservedObject var viewModel: JarvisViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textInput = ""
    @State private var isShowingLaunch = true

    var body: some View {
        ZStack {
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
        .frame(minWidth: 520, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if viewModel.messages.isEmpty {
                viewModel.start()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JARVIS")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(viewModel.backendStatus.color)
                        .frame(width: 8, height: 8)
                    Text(viewModel.backendStatus == .online ? "LOCAL" : viewModel.backendStatus.label.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(viewModel.backendStatus.color)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 16) {
                OrbView(state: viewModel.state)
                ZStack {
                    Text(viewModel.state.label)
                        .id(viewModel.state.label)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .offset(y: 8).combined(with: .opacity),
                                    removal: .offset(y: -8).combined(with: .opacity)
                                )
                        )
                }
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42), value: viewModel.state.label)

                if viewModel.state == .listening {
                    WaveformView(levels: viewModel.microphone.levels)
                }
            }

            Spacer()

            ConversationView(messages: viewModel.messages)
                .frame(maxHeight: 260)
                .opacity(viewModel.messages.isEmpty ? 0.4 : 1)

            Divider().padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button {
                    if viewModel.state == .listening {
                        viewModel.stopListening()
                    } else {
                        viewModel.startListening()
                    }
                } label: {
                    Label(
                        viewModel.state == .listening ? "Parar" : "Microfone",
                        systemImage: viewModel.state == .listening ? "stop.circle.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state != .listening && !viewModel.canStartInteraction)

                if viewModel.canInterrupt {
                    Button("Interromper", role: .cancel) {
                        viewModel.stopEverything()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.messages.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            HStack {
                TextField("Pergunte ao Jarvis...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.canStartInteraction)
                    .onSubmit {
                        viewModel.sendText(textInput)
                        textInput = ""
                    }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Text(viewModel.footerModels)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }
}
