import Foundation

/// The local tier: an Ollama server on localhost speaking the OpenAI-compatible
/// API. Qwen 3 8B is the constitution's default local target (execution-first:
/// tool use, planning, structured output). MLX can replace this runtime later
/// behind the same `ModelProvider` protocol without touching any consumer.
///
/// Generation reuses the proven `OpenAICompatibleClient` transport; this type
/// adds identity, the model default, and a fast availability probe so routing
/// can fall back to cloud instantly when no local server is running.
struct OllamaProvider: ModelProvider {
    static let defaultModel = "qwen3:8b"
    static let baseURL = "http://localhost:11434/v1"

    let id = "local-ollama"
    let model: String
    private let probe: @Sendable () async -> Bool
    private let client: OpenAICompatibleClient

    init(model: String = OllamaProvider.defaultModel,
         probe: (@Sendable () async -> Bool)? = nil) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultModel : trimmed
        self.model = resolved
        self.probe = probe ?? Self.defaultProbe
        self.client = OpenAICompatibleClient(
            label: "Ollama",
            baseURL: Self.baseURL,
            models: [resolved],
            keyProvider: { nil },
            requiresKey: false)
    }

    func isAvailable() async -> Bool { await probe() }

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await client.generateText(prompt: prompt, temperature: temperature)
    }

    /// Streaming conversation through Ollama's NATIVE /api/chat — not the
    /// OpenAI-compatible /v1 endpoint, because only the native API honors
    /// `think: false`. Without it, thinking models (Qwen 3.5) burn minutes of
    /// hidden reasoning per turn (measured: 17s for "name two colors" via /v1
    /// vs ~2s native). Supports tool-calling; yields the same StreamEvents as
    /// the Gemini pipeline.
    func streamChat(transcript: String, history: [ConversationTurn],
                    system: String, specs: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        let model = self.model
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "http://localhost:11434/api/chat") else {
                        throw GeminiClient.GeminiError.decodeFailed("bad ollama url")
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 30
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var payload: [String: Any] = [
                        "model": model,
                        "messages": OpenAICompatibleClient.messages(system: system, history: history, user: transcript),
                        "stream": true,
                        "think": false,
                        "options": ["temperature": 0.5]
                    ]
                    let tools = OpenAICompatibleClient.tools(from: specs)
                    if !tools.isEmpty { payload["tools"] = tools }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw GeminiClient.GeminiError.decodeFailed("ollama chat http error")
                    }
                    for try await line in bytes.lines {
                        for ev in Self.events(fromChatLine: Data(line.utf8)) {
                            continuation.yield(ev)
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

    /// One NDJSON line from /api/chat → stream events. Thinking tokens are
    /// dropped; tool-call arguments are stringified like the OpenAI path.
    static func events(fromChatLine data: Data) -> [StreamEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { return [] }
        var out: [StreamEvent] = []
        if let content = message["content"] as? String, !content.isEmpty {
            out.append(.text(content))
        }
        for call in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let fn = call["function"] as? [String: Any],
                  let name = fn["name"] as? String else { continue }
            var args: [String: String] = [:]
            for (k, v) in fn["arguments"] as? [String: Any] ?? [:] {
                args[k] = v as? String ?? "\(v)"
            }
            out.append(.functionCall(name: name, args: args))
        }
        return out
    }

    /// 1.5s HEAD-style probe against Ollama's tag listing. Dead server → false
    /// fast; routing then goes cloud without the user noticing.
    private static let defaultProbe: @Sendable () async -> Bool = {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
