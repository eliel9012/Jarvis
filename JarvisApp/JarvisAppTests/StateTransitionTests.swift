import XCTest
@testable import Jarvis

final class StateTransitionTests: XCTestCase {
    func testJarvisStateEquatable() {
        XCTAssertEqual(JarvisState.idle, JarvisState.idle)
        XCTAssertNotEqual(JarvisState.listening, JarvisState.thinking)
        XCTAssertEqual(JarvisState.error("x"), JarvisState.error("x"))
        XCTAssertNotEqual(JarvisState.error("x"), JarvisState.error("y"))
    }

    func testJarvisStateLabels() {
        XCTAssertEqual(JarvisState.idle.label, "Ocioso")
        XCTAssertEqual(JarvisState.listening.label, "Ouvindo...")
        XCTAssertEqual(JarvisState.thinking.label, "Pensando...")
        XCTAssertEqual(JarvisState.synthesizing.label, "Gerando voz...")
        XCTAssertEqual(JarvisState.speaking.label, "Falando...")
        XCTAssertTrue(JarvisState.error("boom").label.contains("boom"))
        XCTAssertEqual(JarvisState.listening.detail, "Fale naturalmente")
        XCTAssertEqual(JarvisState.thinking.detail, "Criando uma resposta")
    }

    func testHistoryTrimming() {
        let messages = (0..<50).map { i in
            ChatMessage(role: i % 2 == 0 ? "user" : "assistant", content: "msg \(i)")
        }
        let trimmed = ConversationHistory.trimmed(messages, tokenBudget: 10)
        XCTAssertEqual(trimmed.count, 10)
        XCTAssertEqual(trimmed.first?.content, "msg 40")
        XCTAssertEqual(trimmed.last?.content, "msg 49")
    }

    func testHistoryKeptWhenSmall() {
        let messages = [ChatMessage(role: "user", content: "oi")]
        XCTAssertEqual(ConversationHistory.trimmed(messages).count, 1)
    }

    @MainActor
    func testHistoryPersistsTypedTextAndSTTTranscripts() {
        let store = HistoryStore(inMemory: true)
        store.append(role: "user", text: "mensagem digitada", source: .typed)
        store.append(role: "user", text: "transcrição do microfone", source: .stt)
        store.append(role: "assistant", text: "resposta", source: .assistant)

        let conversation = try! XCTUnwrap(store.allConversations().first)
        let saved = store.messages(for: conversation)
        XCTAssertEqual(saved.map(\.text), ["mensagem digitada", "transcrição do microfone", "resposta"])
        XCTAssertEqual(saved.map(\.source), ["typed", "stt", "assistant"])
    }

    @MainActor
    func testHistoryGeneratesTitleFromFirstUserMessage() {
        let store = HistoryStore(inMemory: true)
        store.append(role: "user", text: "Qual a previsão do tempo pra amanhã em São Paulo?", source: .typed)

        let conversation = try! XCTUnwrap(store.allConversations().first)
        XCTAssertTrue(conversation.title.hasPrefix("Qual a previsão do tempo"))
        XCTAssertNotEqual(conversation.title, "Conversa")
    }

    @MainActor
    func testHistoryResumeContinuesSameConversationInsteadOfCreatingNew() {
        let store = HistoryStore(inMemory: true)
        store.append(role: "user", text: "primeira pergunta", source: .typed)
        store.append(role: "assistant", text: "primeira resposta", source: .assistant)
        store.startNewConversation()
        let original = try! XCTUnwrap(store.allConversations().first)

        store.resume(original)
        store.append(role: "user", text: "pergunta de retomada", source: .typed)

        XCTAssertEqual(store.allConversations().count, 1)
        XCTAssertEqual(
            store.messages(for: original).map(\.text),
            ["primeira pergunta", "primeira resposta", "pergunta de retomada"]
        )
    }

    func testTemporaryAudioIsRemoved() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis_tts_\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        TemporaryAudioFiles.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
