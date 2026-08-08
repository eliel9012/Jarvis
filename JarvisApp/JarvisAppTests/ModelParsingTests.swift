import XCTest
@testable import Jarvis

final class ModelParsingTests: XCTestCase {
    func testConversationResponseDecoding() throws {
        let json = """
        {
          "transcript": "Jarvis, você consegue me ouvir?",
          "response": "Ouvindo perfeitamente.",
          "reasoning": null,
          "audio_path": "/Users/x/Audio/output/1.wav",
          "audio_duration_s": 2.4,
          "latency_s": 23.7,
          "llm_latency_s": 3.1,
          "tts_rtf": 1.2,
          "stt_processing_s": 1.9
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ConversationResponse.self, from: json)
        XCTAssertEqual(decoded.transcript, "Jarvis, você consegue me ouvir?")
        XCTAssertEqual(decoded.response, "Ouvindo perfeitamente.")
        XCTAssertEqual(decoded.audio_path, "/Users/x/Audio/output/1.wav")
    }

    func testChatResponseWithReasoning() throws {
        let json = """
        {
          "content": "",
          "reasoning": "vou responder",
          "latency_s": 2.3,
          "usage": {"prompt_tokens": 10, "completion_tokens": 40, "total_tokens": 50}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: json)
        XCTAssertTrue(decoded.content.isEmpty)
        XCTAssertEqual(decoded.reasoning, "vou responder")
        XCTAssertEqual(decoded.usage?.total_tokens, 50)
    }

    func testModelsResponseDecoding() throws {
        let json = """
        {
          "llm": {"model": "qwen/qwen3.5-9b", "available": ["a", "b"]},
          "stt": "whisper",
          "tts": {"model": "qwen3-tts", "language": "Portuguese"}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: json)
        XCTAssertEqual(decoded.llm?.model, "qwen/qwen3.5-9b")
        XCTAssertEqual(decoded.tts?.model, "qwen3-tts")
        XCTAssertEqual(decoded.tts?.language, "Portuguese")
    }

    func testChatMessageRoundTrip() throws {
        let msg = ChatMessage(role: "user", content: "olá")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, "user")
        XCTAssertEqual(decoded.content, "olá")
        XCTAssertEqual(decoded.source, .typed)
    }
}
