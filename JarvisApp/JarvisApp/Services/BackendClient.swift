import Foundation

/// Cliente HTTP para o backend local JARVIS (127.0.0.1:8765).
struct BackendClient {
    static let shared = BackendClient()
    static let defaultBaseURL = URL(string: "http://127.0.0.1:8765")!

    var baseURL: URL
    private let session: URLSession

    init(baseURL: URL = BackendClient.defaultBaseURL, configuration: URLSessionConfiguration? = nil) {
        self.baseURL = baseURL
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.httpStatus(response: response)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.httpStatus(response: response)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func multipart<T: Decodable>(
        _ path: String,
        file: URL,
        fields: [String: String] = [:]
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        for (key, value) in fields {
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        }
        let filename = file.lastPathComponent
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: file))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.httpStatus(response: response)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func health() async throws -> HealthResponse {
        try await get("health")
    }

    func models() async throws -> ModelsResponse {
        try await get("models")
    }

    func chat(
        messages: [ChatMessage],
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> ChatResponse {
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": maxTokens ?? 2048,
        ]
        if let temperature { body["temperature"] = temperature }
        return try await postJSON("chat", body: body)
    }

    func stt(file: URL) async throws -> STTResponse {
        try await multipart("stt", file: file)
    }

    func tts(text: String, model: String? = nil, speed: Double = 1.0, refAudio: String? = nil, refText: String? = nil) async throws -> TTSResponse {
        var body: [String: Any] = ["text": text, "speed": speed]
        if let model { body["model"] = model }
        if let refAudio { body["ref_audio"] = refAudio }
        if let refText { body["ref_text"] = refText }
        return try await postJSON("tts", body: body)
    }

    func conversation(file: URL, mode: String = "quality", speed: Double = 1.0) async throws -> ConversationResponse {
        try await multipart("conversation", file: file, fields: ["mode": mode, "speed": String(speed)])
    }

    func ping() async -> Bool {
        (try? await health()) != nil
    }
}

enum BackendError: LocalizedError {
    case httpStatus(response: URLResponse)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let response):
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-debug") ?? ""
            return "Backend respondeu com status \(code)\(body.isEmpty ? "" : " (\(body))")"
        }
    }
}
