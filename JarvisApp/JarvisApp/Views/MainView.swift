import SwiftUI

/// Tela principal do Jarvis.
struct MainView: View {
    @ObservedObject var viewModel: JarvisViewModel
    @State private var textInput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JARVIS")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(viewModel.backendStatus.color)
                        .frame(width: 8, height: 8)
                    Text("LOCAL")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 16) {
                OrbView(state: viewModel.state)
                Text(viewModel.state.label)
                    .font(.title2)
                    .foregroundStyle(.secondary)
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

                Button("Stop Speaking") {
                    viewModel.stopEverything()
                }
                .buttonStyle(.bordered)

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
                TextField("Ask Jarvis...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
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
        .frame(minWidth: 520, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if viewModel.messages.isEmpty {
                viewModel.start()
            }
        }
    }
}
