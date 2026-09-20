import Foundation

struct ClaudeMessage: Codable {
    var role: String
    var content: String
}

enum ClaudeError: LocalizedError {
    case noKey, http(Int, String), badResponse, refusal(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "No Claude API key set. Add one in Settings."
        case .http(let code, let body):
            if body.contains("anthropic-workspace-id") { return "Your Claude key needs a Workspace ID. Add it in Settings (console.anthropic.com → Settings → Workspaces)." }
            if let d = body.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let e = o["error"] as? [String: Any], let msg = e["message"] as? String { return "Claude API error \(code): \(msg)" }
            return "Claude API error \(code): \(body.prefix(300))"
        case .badResponse: return "Unexpected response from Claude."
        case .refusal(let why): return "Claude declined this request: \(why)"
        }
    }
}

/// Raw HTTPS client for the Claude Messages API (no Swift SDK exists).
final class ClaudeClient {
    static let shared = ClaudeClient()
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private func request(body: [String: Any], stream: Bool) throws -> URLRequest {
        guard let key = Settings.shared.claudeKey, !key.isEmpty else { throw ClaudeError.noKey }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let ws = Settings.shared.claudeWorkspace.trimmingCharacters(in: .whitespaces)
        if !ws.isEmpty { req.setValue(ws, forHTTPHeaderField: "anthropic-workspace-id") }
        var b = body
        b["model"] = Settings.shared.claudeModel
        b["fallbacks"] = "default"
        if stream { b["stream"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        return req
    }

    /// One-shot completion. `system` may be a plain string or an array of blocks (for cache_control).
    func complete(system: Any, messages: [ClaudeMessage], maxTokens: Int = 16000,
                  effort: String = "medium", jsonSchema: [String: Any]? = nil) async throws -> String {
        var body: [String: Any] = [
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "output_config": jsonSchema.map { ["effort": effort, "format": ["type": "json_schema", "schema": $0]] } ?? ["effort": effort],
        ]
        body["thinking"] = ["type": "adaptive"]
        let req = try request(body: body, stream: false)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        if json["stop_reason"] as? String == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw ClaudeError.refusal(details?["explanation"] as? String ?? "safety policy")
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        return text
    }

    /// Streams text deltas via SSE.
    func stream(system: Any, messages: [ClaudeMessage], maxTokens: Int = 16000, effort: String = "medium") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = [
                        "max_tokens": maxTokens,
                        "system": system,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "output_config": ["effort": effort],
                        "thinking": ["type": "adaptive"],
                    ]
                    let req = try request(body: body, stream: true)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw ClaudeError.badResponse }
                    if !(200..<300).contains(http.statusCode) {
                        var buf = ""
                        for try await line in bytes.lines { buf += line }
                        throw ClaudeError.http(http.statusCode, buf)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        let type = obj["type"] as? String
                        if type == "content_block_delta",
                           let delta = obj["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let t = delta["text"] as? String {
                            continuation.yield(t)
                        } else if type == "message_delta",
                                  let delta = obj["delta"] as? [String: Any],
                                  delta["stop_reason"] as? String == "refusal" {
                            throw ClaudeError.refusal("safety policy")
                        } else if type == "error" {
                            let e = obj["error"] as? [String: Any]
                            throw ClaudeError.http(0, e?["message"] as? String ?? "stream error")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
