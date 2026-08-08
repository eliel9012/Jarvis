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
        XCTAssertTrue(JarvisState.error("boom").label.contains("boom"))
    }

    func testHistoryTrimming() {
        let messages = (0..<50).map { i in
            ChatMessage(role: i % 2 == 0 ? "user" : "assistant", content: "msg \(i)")
        }
        let trimmed = ConversationHistory.trimmed(messages, maxCount: 10)
        XCTAssertEqual(trimmed.count, 10)
        XCTAssertEqual(trimmed.first?.content, "msg 40")
        XCTAssertEqual(trimmed.last?.content, "msg 49")
    }

    func testHistoryKeptWhenSmall() {
        let messages = [ChatMessage(role: "user", content: "oi")]
        XCTAssertEqual(ConversationHistory.trimmed(messages).count, 1)
    }
}
