import SwiftUI

/// Histórico da conversa.
struct ConversationView: View {
    let messages: [ChatMessage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollTarget: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        Text("Pergunte algo ou fale com o Jarvis.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .offset(x: msg.role == "user" ? 18 : -18)
                                            .combined(with: .opacity)
                                            .combined(with: .scale(scale: 0.98)),
                                        removal: .opacity
                                    )
                            )
                    }
                }
                .padding()
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .timingCurve(0.16, 1, 0.3, 1, duration: 0.48),
                    value: messages.count
                )
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(isUser ? "Você" : "Jarvis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .font(.body)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isUser ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                    )
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
