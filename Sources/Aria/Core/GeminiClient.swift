import Foundation

/// Async client for Google's Gemini API (gemini-1.5-flash, vision-capable).
/// Handles structured-JSON output, retry with exponential backoff on 429, and a
/// short identical-request cache. `URLSession` is injectable so tests can mock
/// the transport with no network.
actor GeminiClient {

    enum GeminiError: Error, Equatable {
        case missingAPIKey
        case http(Int)
        case emptyResponse
        case decodeFailed(String)
    }

    struct SystemContext {
        var currentApp: String
        var time: Date
        var username: String
    }

    private let model: String
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    // 30-second identical-request cache.
    private struct CacheEntry { let response: AriaResponse; let at: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 30

    private let maxRetries = 3

    init(model: String = "gemini-flash-latest",
         session: URLSession = .shared,
         apiKeyProvider: @escaping () -> String? = { KeychainManager.read(account: KeychainKey.geminiAPIKey) }) {
        self.model = model
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Send a turn to Gemini and decode the structured AriaResponse.
    func send(transcript: String,
              screenshotJPEG: Data?,
              history: [ConversationTurn],
              context: SystemContext,
              toolCatalog: String = "") async throws -> AriaResponse {

        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let cacheKey = Self.cacheKey(transcript: transcript, image: screenshotJPEG)
        if let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < cacheTTL {
            Log.gemini.debug("Cache hit for request")
            return hit.response
        }

        let body = buildRequestBody(transcript: transcript,
                                    screenshotJPEG: screenshotJPEG,
                                    history: history,
                                    context: context,
                                    toolCatalog: toolCatalog)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let data = try await performWithRetry(url: url, body: body)
        let response = try Self.decodeAriaResponse(from: data)

        cache[cacheKey] = CacheEntry(response: response, at: Date())
        return response
    }

    /// Ask Gemini to write a self-contained script in `language` that performs
    /// `task`. Returns raw code (fences stripped). Used by DynamicToolFactory.
    func generateScript(task: String,
                        language: ToolLanguage,
                        context: SystemContext) async throws -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        let prompt = """
        Write a single, self-contained \(language.rawValue) script that accomplishes this task:

        TASK: \(task)

        Requirements:
        - Output ONLY the code. No explanation, no markdown fences.
        - The script must be runnable as-is with the standard \(language.rawValue) interpreter.
        - Print results to stdout. Exit non-zero on failure.
        - Prefer the standard library; avoid dependencies that need installation.
        - It runs in an isolated temp directory; use absolute paths for user files.
        - System: user \(context.username), app \(context.currentApp).
        """
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2]
        ]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let data = try await performWithRetry(url: url, body: body)
        return Self.stripCodeFences(Self.extractText(from: data))
    }

    static func extractText(from data: Data) -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.compactMap({ $0["text"] as? String }).first
        else { return "" }
        return text
    }

    /// Remove leading/trailing ``` fences (and language tag) if present.
    static func stripCodeFences(_ s: String) -> String {
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Networking + retry

    private func performWithRetry(url: URL, body: Data) async throws -> Data {
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                return data
            }
            if status == 429, attempt < maxRetries {
                let backoff = pow(2.0, Double(attempt)) * 0.5  // 0.5s, 1s, 2s
                Log.gemini.warning("Rate limited (429); retrying in \(backoff)s")
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                attempt += 1
                continue
            }
            throw GeminiError.http(status)
        }
    }

    // MARK: Request building

    private func buildRequestBody(transcript: String,
                                 screenshotJPEG: Data?,
                                 history: [ConversationTurn],
                                 context: SystemContext,
                                 toolCatalog: String) -> Data {
        var parts: [[String: Any]] = []

        let historyText = history.map {
            "User: \($0.transcript)\nAria: \($0.responseMessage)"
        }.joined(separator: "\n")

        let toolsBlock = toolCatalog.isEmpty ? "" : """

        AVAILABLE TOOLS (use via "action"/"multi_action"; for anything else emit \
        an action with tool "dynamic" and an "input.task" describing what to do):
        \(toolCatalog)
        """

        let userText = """
        SYSTEM CONTEXT:
        - Current app: \(context.currentApp)
        - Time: \(ISO8601DateFormatter().string(from: context.time))
        - User: \(context.username)
        \(toolsBlock)

        RECENT CONVERSATION:
        \(historyText.isEmpty ? "(none)" : historyText)

        USER COMMAND:
        \(transcript)
        """

        parts.append(["text": userText])

        if let jpeg = screenshotJPEG {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": jpeg.base64EncodedString()
                ]
            ])
        }

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "temperature": 0.4,
                "response_mime_type": "application/json"
            ]
        ]

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    // MARK: Response decoding

    /// Extract the model text from Gemini's envelope, then decode the inner
    /// AriaResponse JSON. Falls back to wrapping raw text as an `.answer`.
    static func decodeAriaResponse(from data: Data) throws -> AriaResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.compactMap({ $0["text"] as? String }).first
        else {
            throw GeminiError.emptyResponse
        }

        if let inner = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AriaResponse.self, from: inner) {
            return decoded
        }
        // Model didn't honor JSON mode — surface its text as a plain answer.
        return AriaResponse(type: .answer, message: text)
    }

    private static func cacheKey(transcript: String, image: Data?) -> String {
        "\(transcript)#\(image?.count ?? 0)"
    }

    static let systemPrompt = """
    You are Aria, an AI agent running natively on the user's Mac. You see their \
    screen (provided as an image) and hear their voice. You are confident, warm, \
    and a little charming — a sharp personal assistant who has it handled. You act; \
    you don't lecture.

    Voice & tone:
    - Keep "message" to 1–2 short sentences. It is spoken aloud and shown in a small card.
    - Confident and natural, with the occasional light touch of charm. Never campy, \
    never corporate filler, no emoji.
    - Confirm actions crisply: "On it." / "Done — Spotify's up." / "Say the word."

    ALWAYS respond with a single JSON object, no prose outside it, matching this schema:
    {
      "type": "answer" | "action" | "multi_action" | "clarify",
      "message": "short, natural text to show/speak to the user",
      "confidence": 0.0-1.0,
      "actions": [ { "tool": "tool_name", "input": { "key": "value" } } ],
      "followup": "optional follow-up question, or null"
    }

    Use "answer" for direct responses, "clarify" when you genuinely need more info, \
    and "action"/"multi_action" when the task needs tools.
    """
}
