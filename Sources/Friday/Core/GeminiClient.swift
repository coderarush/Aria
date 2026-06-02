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
    private struct CacheEntry { let response: FridayResponse; let at: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 30

    private let maxRetries = 3

    init(model: String = "gemini-1.5-flash",
         session: URLSession = .shared,
         apiKeyProvider: @escaping () -> String? = { KeychainManager.read(account: KeychainKey.geminiAPIKey) }) {
        self.model = model
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Send a turn to Gemini and decode the structured FridayResponse.
    func send(transcript: String,
              screenshotJPEG: Data?,
              history: [ConversationTurn],
              context: SystemContext) async throws -> FridayResponse {

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
                                    context: context)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let data = try await performWithRetry(url: url, body: body)
        let response = try Self.decodeFridayResponse(from: data)

        cache[cacheKey] = CacheEntry(response: response, at: Date())
        return response
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
                                 context: SystemContext) -> Data {
        var parts: [[String: Any]] = []

        let historyText = history.map {
            "User: \($0.transcript)\nFriday: \($0.responseMessage)"
        }.joined(separator: "\n")

        let userText = """
        SYSTEM CONTEXT:
        - Current app: \(context.currentApp)
        - Time: \(ISO8601DateFormatter().string(from: context.time))
        - User: \(context.username)

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
    /// FridayResponse JSON. Falls back to wrapping raw text as an `.answer`.
    static func decodeFridayResponse(from data: Data) throws -> FridayResponse {
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
           let decoded = try? JSONDecoder().decode(FridayResponse.self, from: inner) {
            return decoded
        }
        // Model didn't honor JSON mode — surface its text as a plain answer.
        return FridayResponse(type: .answer, message: text)
    }

    private static func cacheKey(transcript: String, image: Data?) -> String {
        "\(transcript)#\(image?.count ?? 0)"
    }

    static let systemPrompt = """
    You are Friday, an AI AGENT running natively on the user's Mac. You are not a \
    chat assistant — you take actions and get things done. You can see the user's \
    screen (provided as an image) and hear their voice commands.

    ALWAYS respond with a single JSON object, no prose, matching this schema:
    {
      "type": "answer" | "action" | "multi_action" | "clarify",
      "message": "short, natural text to show/speak to the user",
      "confidence": 0.0-1.0,
      "actions": [ { "tool": "tool_name", "input": { "key": "value" } } ],
      "followup": "optional follow-up question, or null"
    }

    Use "answer" for direct responses, "clarify" when you need more info, and \
    "action"/"multi_action" when the task requires running tools. Keep "message" \
    concise and conversational — it will be spoken aloud and shown in a small card.
    """
}
