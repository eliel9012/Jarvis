import XCTest
@testable import Jarvis

/// Mock de URLSession via URLProtocol para testar o BackendClient offline.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("requestHandler não configurado")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class BackendClientTests: XCTestCase {
    private var client: BackendClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = BackendClient(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            configuration: config
        )
    }

    func testHealthParsing() async throws {
        let json = """
        {"status":"ok","local":true,"llm":{"online":true,"base_url":"http://127.0.0.1:1234/v1"},
        "stt":{"model":"whisper","loaded":false},"tts":{"model":"fish","loaded":false}}
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")
        XCTAssertTrue(health.local)
        XCTAssertEqual(health.llm?.online, true)
        XCTAssertEqual(health.llm?.base_url, "http://127.0.0.1:1234/v1")
    }

    func testChatRequestAndParsing() async throws {
        let json = """
        {"content":"Olá, sou o Jarvis.","reasoning":null,"latency_s":0.5,
        "usage":{"prompt_tokens":12,"completion_tokens":5,"total_tokens":17}}
        """
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let msg = ChatMessage(role: "user", content: "oi")
        let chat = try await client.chat(messages: [msg], maxTokens: 128, temperature: 0.7)
        XCTAssertEqual(chat.content, "Olá, sou o Jarvis.")
        XCTAssertEqual(chat.usage?.total_tokens, 17)
    }

    func testSTTMultipartUploadAndParsing() async throws {
        let json = """
        {"text":"voz masculina brasileira","language":"pt","duration":2.0,
        "processing_time":0.08,"rtf":0.04}
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_stt.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/stt")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.allHTTPHeaderFields?["Content-Type"]?.contains("multipart/form-data") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await client.stt(file: tmp)
        XCTAssertEqual(result.text, "voz masculina brasileira")
        XCTAssertEqual(result.language, "pt")
        XCTAssertEqual(result.rtf, 0.04)
    }

    func testConversationMultipartUpload() async throws {
        let json = """
        {"transcript":"olá","response":"tudo bem?","reasoning":null,"audio_path":"/tmp/x.wav",
        "audio_duration_s":2.0,"latency_s":3.0,"llm_latency_s":1.0,"tts_rtf":0.8,"stt_processing_s":0.5}
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_capture.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: tmp)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/conversation")
            let body: Data
            if let httpBody = request.httpBody {
                body = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                body = data
            } else {
                body = Data()
            }
            XCTAssertTrue(body.count > 0)
            XCTAssertTrue(request.allHTTPHeaderFields?["Content-Type"]?.contains("multipart/form-data") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let result = try await client.conversation(file: tmp, mode: "quality", speed: 1.0)
        XCTAssertEqual(result.transcript, "olá")
        XCTAssertEqual(result.response, "tudo bem?")
        XCTAssertEqual(result.audio_path, "/tmp/x.wav")
        try? FileManager.default.removeItem(at: tmp)
    }

    func testHTTPErrorPropagation() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await client.health()
            XCTFail("Deveria lançar erro para status 500")
        } catch {
            // esperado
        }
    }
}
