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

    private let models: [String]
    private let scheduler: RequestScheduler
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    // 30-second identical-request cache.
    private struct CacheEntry { let response: AriaResponse; let at: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 30

    private let maxRetries = 5

    init(model: String = "gemini-2.5-flash",
         session: URLSession = .shared,
         apiKeyProvider: @escaping () -> String? = { KeychainManager.read(account: KeychainKey.geminiAPIKey) }) {
        // Primary model first, then fallbacks (deduped). The free tier meters RPM
        // PER MODEL, so spreading across several models — including the higher-RPM,
        // faster `-lite` variants — multiplies effective free throughput: if one
        // model is rate-limited, the next has its own bucket.
        self.models = [model, "gemini-2.5-flash", "gemini-2.0-flash",
                       "gemini-2.5-flash-lite", "gemini-2.0-flash-lite"]
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        self.scheduler = RequestScheduler(models: self.models)
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Reserve a model bucket, waiting (pacing) if all are momentarily maxed.
    private func reserveModel(preferred: String? = nil) async -> String {
        if let p = preferred { return p }
        if let m = scheduler.reserve() { return m }
        let wait = min(scheduler.waitTime(), 65)
        Log.trace("scheduler: all buckets maxed; pacing \(wait)s")
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        return scheduler.reserve() ?? models[0]
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
        let data = try await performWithFallback(apiKey: apiKey, body: body)
        let response = try Self.decodeAriaResponse(from: data)

        cache[cacheKey] = CacheEntry(response: response, at: Date())
        return response
    }

    /// Stream a turn from Gemini, yielding text deltas + function calls as they
    /// arrive (`streamGenerateContent?alt=sse`). On a transient non-200 before any
    /// bytes are received, falls through to the next model in `models`. A mid-
    /// stream failure surfaces via the stream's error (caller speaks a recovery).
    func streamSend(transcript: String,
                    screenshotJPEG: Data?,
                    history: [ConversationTurn],
                    context: SystemContext,
                    toolCatalog: String = "",
                    tools: [[String: Any]]? = nil,
                    preferredModel: String? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                        throw GeminiError.missingAPIKey
                    }
                    let body = buildRequestBody(transcript: transcript,
                                                screenshotJPEG: screenshotJPEG,
                                                history: history, context: context,
                                                toolCatalog: toolCatalog,
                                                tools: tools,
                                                jsonMode: false)
                    var lastError: Error = GeminiError.emptyResponse
                    let maxAttempts = 6
                    for attempt in 0..<maxAttempts {
                        // First attempt may honor a routed preferredModel; otherwise reserve a bucket (pacing if needed).
                        let model = await reserveModel(preferred: attempt == 0 ? preferredModel : nil)
                        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.httpBody = body
                        do {
                            let (bytes, resp) = try await session.bytes(for: req)
                            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                            guard status == 200 else { throw GeminiError.http(status) }
                            var parser = GeminiStreamParser()
                            for try await line in bytes.lines {
                                try Task.checkCancellation()
                                for ev in parser.consume(line + "\n") { continuation.yield(ev) }
                            }
                            continuation.finish()
                            return
                        } catch let GeminiError.http(status) where [404, 408, 425, 429, 500, 502, 503, 504].contains(status) {
                            lastError = GeminiError.http(status)
                            Log.trace("streamSend: \(model) http(\(status)); attempt \(attempt + 1)/\(maxAttempts)")
                            continue   // reserveModel paces on the next iteration if all buckets are maxed
                        }
                    }
                    continuation.finish(throwing: lastError)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
        let data = try await performWithFallback(apiKey: apiKey, body: body)
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

    /// Transient statuses worth retrying: rate limiting (429), server/overload
    /// (5xx), and — observed with newer "AQ." API keys — intermittent 404s from
    /// the load balancer (the same model returns 200 on a retry).
    private static let retryableStatuses: Set<Int> = [404, 408, 425, 429, 500, 502, 503, 504]

    private func backoffSeconds(_ attempt: Int) -> Double {
        min(pow(2.0, Double(attempt)) * 0.4, 6)  // 0.4, 0.8, 1.6, 3.2, 6 …
    }

    private func performWithRetry(url: URL, body: Data) async throws -> Data {
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let data: Data
            let status: Int
            do {
                let (d, response) = try await session.data(for: request)
                data = d
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                // Network-level failure (timeout, dropped connection) — retry too.
                guard attempt < self.maxRetries else { throw error }
                try await Task.sleep(nanoseconds: UInt64(self.backoffSeconds(attempt) * 1_000_000_000))
                attempt += 1
                continue
            }

            if status == 200 { return data }

            if Self.retryableStatuses.contains(status), attempt < self.maxRetries {
                let backoff = self.backoffSeconds(attempt)
                Log.gemini.warning("HTTP \(status); retry \(attempt + 1)/\(self.maxRetries) in \(backoff)s")
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                attempt += 1
                continue
            }
            throw GeminiError.http(status)
        }
    }

    /// Try each configured model in order; if one keeps failing after retries
    /// (e.g. a model that 404s or stays overloaded for this key), fall through to
    /// the next. Throws the last error only if every model fails.
    private func performWithFallback(apiKey: String, body: Data) async throws -> Data {
        var lastError: Error = GeminiError.emptyResponse
        for model in models {
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
            do {
                let data = try await performWithRetry(url: url, body: body)
                Log.trace("gemini: \(model) ok")
                return data
            } catch {
                Log.trace("gemini: \(model) failed (\(error)); trying next model")
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: Request building

    private func buildRequestBody(transcript: String,
                                 screenshotJPEG: Data?,
                                 history: [ConversationTurn],
                                 context: SystemContext,
                                 toolCatalog: String,
                                 tools: [[String: Any]]? = nil,
                                 jsonMode: Bool = true) -> Data {
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

        // JSON response mode is for the structured (non-streaming) path only. The
        // streaming voice path must emit natural prose + function calls, so it
        // passes jsonMode:false (forcing JSON would make her speak JSON).
        var generationConfig: [String: Any] = ["temperature": 0.4]
        if jsonMode { generationConfig["response_mime_type"] = "application/json" }
        var payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig
        ]

        if let tools, !tools.isEmpty {
            payload["tools"] = [["functionDeclarations": tools]]
        }

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
    You are Aria, an AI agent that lives on the user's Mac. You talk with the user \
    in a natural, back-and-forth voice conversation — your replies are spoken aloud, \
    so keep them short, warm, and natural (usually one or two sentences). You are \
    confident and a little charming: a sharp personal assistant who has it handled. \
    Never campy, no corporate filler, no emoji, and never read JSON, markdown, or \
    tool names aloud.

    Answer general questions and well-known facts — including trivia and fun facts \
    — directly from your own knowledge. Do NOT use web_search for things you \
    already know; only search for current events, live data, or specifics you \
    genuinely don't know. Never reply that you "couldn't find anything" for a \
    general-knowledge question — just answer it.

    You can see the user's screen when it's provided, and you have tools available \
    (as functions) to take real actions on the Mac (open apps, files, etc.) — use \
    them to actually do what the user asks instead of just describing it. You can \
    work in multiple steps: call a tool, see the result, then continue or give your \
    final spoken answer. If you genuinely need more information, ask one brief \
    clarifying question instead of guessing.
    """
}
