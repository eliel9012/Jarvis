import Foundation
import SwiftData

/// Modelo de persistência (SwiftData) para o histórico de conversa.
@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord]

    init(id: UUID = UUID(), title: String = "Conversa", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = []
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var role: String
    var text: String
    var timestamp: Date
    var conversation: ConversationRecord?

    init(id: UUID = UUID(), role: String, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Armazena e recupera o histórico via SwiftData.
@MainActor
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var current: ConversationRecord?

    init() {
        let schema = Schema([ConversationRecord.self, MessageRecord.self])
        let config = ModelConfiguration("JarvisHistory", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Falha ao criar ModelContainer: \(error)")
        }
    }

    func append(role: String, text: String) {
        if current == nil {
            let conv = ConversationRecord()
            context.insert(conv)
            current = conv
        }
        guard let current else { return }
        let msg = MessageRecord(role: role, text: text)
        context.insert(msg)
        msg.conversation = current
        current.messages.append(msg)
        try? context.save()
    }

    func allConversations() -> [ConversationRecord] {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func messages(for conversation: ConversationRecord) -> [MessageRecord] {
        conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    func deleteAll() {
        try? context.delete(model: ConversationRecord.self)
        current = nil
        try? context.save()
    }
}
