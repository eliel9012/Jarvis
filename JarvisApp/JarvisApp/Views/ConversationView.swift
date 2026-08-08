import SwiftUI

/// Histórico compacto em linhas, como na referência visual.
struct ConversationView: View {
    let messages: [ChatMessage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(messages.suffix(4))) { message in
                ConversationRow(message: message)
                    .id(message.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(JarvisTheme.border.opacity(0.34))
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if messages.isEmpty {
                    Text("Pergunte algo ou fale com Jarvis.")
                        .font(.system(size: 14))
                        .foregroundStyle(JarvisTheme.secondaryText)
                }
            }
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42), value: messages.count)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

private struct ConversationRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }
    private var label: String {
        if !isUser { return "JARVIS" }
        return message.source == .stt ? "VOCÊ · VOZ" : "VOCÊ · digitado"
    }

    var body: some View {
        HStack(spacing: 20) {
            Rectangle()
                .fill(isUser ? Color.white.opacity(0.9) : JarvisTheme.cyan)
                .frame(width: 3, height: 34)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isUser ? JarvisTheme.secondaryText : JarvisTheme.cyan)
                .frame(width: 128, alignment: .leading)

            Text(message.content)
                .font(.system(size: 16))
                .foregroundStyle(JarvisTheme.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
