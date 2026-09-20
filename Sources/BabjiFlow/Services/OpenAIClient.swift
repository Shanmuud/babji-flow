import Foundation

/// Raw HTTPS client for OpenAI Chat Completions (same shape as ClaudeClient).
final class OpenAIClient {
    static let shared = OpenAIClient()
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    enum OpenAIError: LocalizedError {
        case noKey, http(Int, String), badResponse
        var errorDescription: String? {
            switch self {
            case .noKey: return "No OpenAI API key set. Add one in Settings."
            case .http(let code, let body):
                if let d = body.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let e = o["error"] as? [String: Any], let msg = e["message"] as? String { return "OpenAI error \(code): \(msg)" }
                return "OpenAI error \(code): \(body.prefix(300))"
            case .badResponse: return "Unexpected response from OpenAI."
            }
        }
    }

    private func request(system: String, messages: [ClaudeMessage], model: String, maxTokens: Int,
                         effort: String, jsonSchema: [String: Any]?, stream: Bool) throws -> URLRequest {
        guard let key = Settings.shared.openaiKey, !key.isEmpty else { throw OpenAIError.noKey }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        msgs += messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": model, "messages": msgs, "max_completion_tokens": maxTokens]
        // Reasoning models accept reasoning_effort; "*-chat-latest" variants do not.
        if model.hasPrefix("gpt-5"), !model.contains("chat") {
            body["reasoning_effort"] = ["low": "low", "medium": "medium", "high": "high"][effort] ?? "low"
        }
        if let schema = jsonSchema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": "result", "strict": true, "schema": schema]]
        }
        if stream { body["stream"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// `system` may be a String or Claude-style array of text blocks (flattened).
    static func flatten(_ system: Any) -> String {
        if let s = system as? String { return s }
        if let blocks = system as? [[String: Any]] { return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n\n") }
        return ""
    }

    func complete(system: Any, messages: [ClaudeMessage], model: String? = nil, maxTokens: Int = 16000,
                  effort: String = "low", jsonSchema: [String: Any]? = nil) async throws -> String {
        let req = try request(system: Self.flatten(system), messages: messages, model: model ?? Settings.shared.openaiModel,
                              maxTokens: maxTokens, effort: effort, jsonSchema: jsonSchema, stream: false)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenAIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else { throw OpenAIError.badResponse }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw OpenAIError.http(200, refusal) }
        return message["content"] as? String ?? ""
    }

    func stream(system: Any, messages: [ClaudeMessage], model: String? = nil, maxTokens: Int = 16000, effort: String = "medium") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request(system: Self.flatten(system), messages: messages, model: model ?? Settings.shared.openaiModel,
                                          maxTokens: maxTokens, effort: effort, jsonSchema: nil, stream: true)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
                    if !(200..<300).contains(http.statusCode) {
                        var buf = ""; for try await line in bytes.lines { buf += line }
                        throw OpenAIError.http(http.statusCode, buf)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]], let c = choices.first,
                              let delta = c["delta"] as? [String: Any], let t = delta["content"] as? String else { continue }
                        continuation.yield(t)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openai, claude
    var id: String { rawValue }
    var label: String { self == .openai ? "OpenAI" : "Claude" }
}

/// Provider-agnostic entry point used by polish, summaries and chat.
enum LLM {
    static var hasKey: Bool {
        Settings.shared.provider == .openai ? Settings.shared.hasOpenAIKey : Settings.shared.hasClaudeKey
    }
    static var missingKeyMessage: String {
        Settings.shared.provider == .openai ? "Add an OpenAI API key in Settings." : "Add a Claude API key in Settings."
    }
    static func complete(system: Any, messages: [ClaudeMessage], maxTokens: Int = 16000, effort: String = "medium",
                         jsonSchema: [String: Any]? = nil, fast: Bool = false) async throws -> String {
        switch Settings.shared.provider {
        case .openai:
            let model = fast ? Settings.shared.openaiFastModel : Settings.shared.openaiModel
            return try await OpenAIClient.shared.complete(system: system, messages: messages, model: model, maxTokens: maxTokens, effort: effort, jsonSchema: jsonSchema)
        case .claude:
            return try await ClaudeClient.shared.complete(system: system, messages: messages, maxTokens: maxTokens, effort: effort, jsonSchema: jsonSchema)
        }
    }
    static func stream(system: Any, messages: [ClaudeMessage], maxTokens: Int = 16000, effort: String = "medium") -> AsyncThrowingStream<String, Error> {
        switch Settings.shared.provider {
        case .openai: return OpenAIClient.shared.stream(system: system, messages: messages, maxTokens: maxTokens, effort: effort)
        case .claude: return ClaudeClient.shared.stream(system: system, messages: messages, maxTokens: maxTokens, effort: effort)
        }
    }
}
