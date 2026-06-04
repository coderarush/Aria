import Foundation

/// One client for every OpenAI-compatible provider — Groq, Cerebras, OpenRouter, and
/// a local Ollama server all speak the same `/chat/completions` API. Aria uses these
/// as fallbacks so that when the Gemini free tier hits its daily cap, the answer keeps
/// coming (Groq is free AND faster) instead of failing. Stacking several free
/// providers is what makes "free forever" actually true.
actor OpenAICompatibleClient {
    let label: String
    private let baseURL: String          // e.g. https://api.groq.com/openai/v1
    private let models: [String]
    private let keyProvider: () -> String?
    private let requiresKey: Bool
    private let session: URLSession

    init(label: String, baseURL: String, models: [String],
         keyProvider: @escaping () -> String?, requiresKey: Bool = true,
         session: URLSession = .shared) {
        self.label = label
        self.baseURL = baseURL
        self.models = models
        self.keyProvider = keyProvider
        self.requiresKey = requiresKey
        self.session = session
    }

    func hasCredentials() -> Bool {
        requiresKey ? !((keyProvider() ?? "").isEmpty) : true
    }

    private func authorizedRequest(path: String) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresKey, let key = keyProvider(), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Plain text generation (planner, agents, synthesis).
    func generateText(prompt: String, temperature: Double = 0.3) async throws -> String {
        guard hasCredentials() else { throw GeminiClient.GeminiError.missingAPIKey }
        var lastError: Error = GeminiClient.GeminiError.emptyResponse
        for model in models {
            guard var req = authorizedRequest(path: "/chat/completions") else { continue }
            let payload: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": prompt]],
                "temperature": temperature
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            do {
                let (data, resp) = try await session.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { lastError = GeminiClient.GeminiError.http(status); continue }
                if let text = Self.contentText(from: data), !text.isEmpty {
                    Log.trace("\(label): \(model) ok")
                    return GeminiClient.stripCodeFences(text)
                }
                lastError = GeminiClient.GeminiError.emptyResponse
            } catch { lastError = error }
        }
        throw lastError
    }

    /// Streaming chat with tool-calling (the chat path), normalized to StreamEvent.
    func streamChat(transcript: String, history: [ConversationTurn],
                    system: String, specs: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard hasCredentials() else { throw GeminiClient.GeminiError.missingAPIKey }
                    var lastError: Error = GeminiClient.GeminiError.emptyResponse
                    for model in models {
                        guard var req = authorizedRequest(path: "/chat/completions") else { continue }
                        var payload: [String: Any] = [
                            "model": model,
                            "messages": Self.messages(system: system, history: history, user: transcript),
                            "stream": true
                        ]
                        let tools = Self.tools(from: specs)
                        if !tools.isEmpty { payload["tools"] = tools }
                        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                        do {
                            let (bytes, resp) = try await session.bytes(for: req)
                            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                            guard status == 200 else { lastError = GeminiClient.GeminiError.http(status); continue }
                            var calls = OpenAIToolCallAccumulator()
                            for try await line in bytes.lines {
                                try Task.checkCancellation()
                                guard line.hasPrefix("data: ") else { continue }
                                let payloadStr = String(line.dropFirst(6))
                                if payloadStr == "[DONE]" { break }
                                guard let d = payloadStr.data(using: .utf8),
                                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                                      let choices = obj["choices"] as? [[String: Any]],
                                      let delta = choices.first?["delta"] as? [String: Any] else { continue }
                                if let content = delta["content"] as? String, !content.isEmpty {
                                    continuation.yield(.text(content))
                                }
                                if let tc = delta["tool_calls"] as? [[String: Any]] { calls.consume(tc) }
                            }
                            for call in calls.finalized() { continuation.yield(.functionCall(name: call.name, args: call.args)) }
                            continuation.finish()
                            return
                        } catch { lastError = error; continue }
                    }
                    continuation.finish(throwing: lastError)
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Pure helpers (testable)

    static func contentText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    static func messages(system: String, history: [ConversationTurn], user: String) -> [[String: String]] {
        var msgs: [[String: String]] = [["role": "system", "content": system]]
        for turn in history {
            msgs.append(["role": "user", "content": turn.transcript])
            if !turn.responseMessage.isEmpty { msgs.append(["role": "assistant", "content": turn.responseMessage]) }
        }
        msgs.append(["role": "user", "content": user])
        return msgs
    }

    static func tools(from specs: [ToolSpec]) -> [[String: Any]] {
        specs.map { spec in
            var properties: [String: Any] = [:]
            for (k, desc) in spec.params { properties[k] = ["type": "string", "description": desc] }
            return [
                "type": "function",
                "function": [
                    "name": spec.name,
                    "description": spec.description,
                    "parameters": ["type": "object", "properties": properties]
                ]
            ]
        }
    }
}

/// Accumulates OpenAI streaming `tool_calls` fragments (name in the first chunk,
/// arguments streamed across chunks, keyed by index) into finished calls.
struct OpenAIToolCallAccumulator {
    private var byIndex: [Int: (name: String, args: String)] = [:]

    mutating func consume(_ fragments: [[String: Any]]) {
        for frag in fragments {
            let idx = frag["index"] as? Int ?? 0
            let fn = frag["function"] as? [String: Any]
            var entry = byIndex[idx] ?? (name: "", args: "")
            if let name = fn?["name"] as? String, !name.isEmpty { entry.name = name }
            if let args = fn?["arguments"] as? String { entry.args += args }
            byIndex[idx] = entry
        }
    }

    func finalized() -> [(name: String, args: [String: String])] {
        byIndex.sorted { $0.key < $1.key }.compactMap { _, v in
            guard !v.name.isEmpty else { return nil }
            let args: [String: String]
            if let d = v.args.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                args = obj.reduce(into: [String: String]()) { $0[$1.key] = String(describing: $1.value) }
            } else { args = [:] }
            return (v.name, args)
        }
    }
}
