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
        // Ambient screen awareness (empty unless granted + non-private). Lets the model
        // resolve "this / here / her / the selection" without asking.
        var windowTitle: String = ""
        var selection: String = ""
        var focusedField: String = ""
        /// Clipboard text — attached only when the command refers to it (see
        /// ContextRelevance), so private clipboard data never rides along by default.
        var clipboard: String = ""

        /// Extra ambient lines for the SYSTEM CONTEXT block — only what's known, so the
        /// prompt stays tight when nothing is focused.
        var ambientLines: String {
            var out = ""
            if !windowTitle.isEmpty { out += "\n- Active window: “\(windowTitle)”" }
            if !focusedField.isEmpty { out += "\n- Focused field: \(focusedField)" }
            if !selection.isEmpty {
                let s = selection.count > 600 ? String(selection.prefix(600)) + "…" : selection
                out += "\n- Selected text: “\(s)”"
            }
            if !clipboard.isEmpty {
                let s = clipboard.count > 600 ? String(clipboard.prefix(600)) + "…" : clipboard
                out += "\n- Clipboard: “\(s)”"
            }
            return out
        }
    }

    private let models: [String]
    private let scheduler: RequestScheduler
    private let keyRotator = KeyRotator()
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    // 30-second identical-request cache.
    private struct CacheEntry { let response: AriaResponse; let at: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 30

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

    /// All configured keys. The keychain item may hold several (one per line / comma-
    /// separated) — each Google project has its own free-tier daily quota, so multiple
    /// free keys multiply the free ceiling.
    private func currentKeys() -> [String] {
        let raw = apiKeyProvider() ?? ""
        return raw.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Reserve a usable key, refreshing the pool and pacing briefly if all keys are
    /// momentarily quota-blocked. Returns nil only when NO keys are configured.
    private func reserveKey(paceIfBlocked: Bool) async -> String? {
        keyRotator.update(keys: currentKeys())
        if keyRotator.isEmpty { return nil }
        if let k = keyRotator.reserve() { return k }
        guard paceIfBlocked else { return nil }
        let wait = min(max(keyRotator.waitTime(), 0.5), 8)
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        return keyRotator.reserve()
    }

    private func reserveModel(preferred: String? = nil) async -> String {
        if let p = preferred { scheduler.record(p); return p }
        while true {
            if let m = scheduler.reserve() { return m }
            let wait = min(max(scheduler.waitTime(), 0.5), 8)
            Log.trace("scheduler: all buckets busy; pacing \(wait)s")
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    /// Build a Gemini request URL with proper percent-encoding for the model and key.
    static func geminiURL(model: String, apiKey: String, streaming: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models/\(model)\(streaming ? ":streamGenerateContent" : ":generateContent")"
        components.queryItems = [
            URLQueryItem(name: "alt", value: streaming ? "sse" : nil),
            URLQueryItem(name: "key", value: apiKey)
        ].compactMap { item in
            if item.name == "alt", item.value == nil { return nil }
            return item
        }
        return components.url
    }

    /// Send a turn to Gemini and decode the structured AriaResponse.
    func send(transcript: String,
              screenshotJPEG: Data?,
              history: [ConversationTurn],
              context: SystemContext,
              toolCatalog: String = "") async throws -> AriaResponse {


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
        let data = try await performWithFallback(body: body)
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
                    specs: [ToolSpec] = [],
                    preferredModel: String? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tools = specs.isEmpty ? nil : ToolDeclarations.declarations(for: specs)
                    keyRotator.update(keys: currentKeys())
                    let body = buildRequestBody(transcript: transcript,
                                                screenshotJPEG: screenshotJPEG,
                                                history: history, context: context,
                                                toolCatalog: toolCatalog,
                                                tools: tools,
                                                jsonMode: false)
                    var lastError: Error = GeminiError.emptyResponse
                    let maxAttempts = 6        // budget for genuinely-broken (5xx/404/…) errors
                    // Interactive chat: pace only briefly to ride out a per-minute spike
                    // (~2 × ~8 s), then fail fast and surface an honest message. A hard
                    // daily-cap (limit:0) won't free for hours — don't hang on "thinking".
                    let maxQuotaWaits = 2
                    var attempt = 0
                    var quotaWaits = 0
                    var first = true
                    // A 429 cools that key+model and routes to the next key/model bucket;
                    // with several free keys this multiplies the free ceiling.
                    while attempt < maxAttempts && quotaWaits < maxQuotaWaits {
                        guard let apiKey = await reserveKey(paceIfBlocked: true) else {
                            quotaWaits += 1; continue   // all keys cooling — bounded, then fail fast
                        }
                        let model = await reserveModel(preferred: first ? preferredModel : nil)
                        first = false
                        guard let url = Self.geminiURL(model: model, apiKey: apiKey, streaming: true) else {
                            lastError = GeminiError.decodeFailed("invalid Gemini request URL")
                            attempt += 1
                            continue
                        }
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
                        } catch let GeminiError.http(status) where status == 429 {
                            lastError = GeminiError.http(status)
                            quotaWaits += 1
                            scheduler.penalize(model, seconds: 8)
                            keyRotator.penalize(apiKey, seconds: 60)   // rotate off this key
                            Log.trace("streamSend: \(model) http(429) quota; rotating key (\(quotaWaits)/\(maxQuotaWaits))")
                            continue
                        } catch let GeminiError.http(status) where [404, 408, 425, 500, 502, 503, 504].contains(status) {
                            lastError = GeminiError.http(status)
                            attempt += 1
                            Log.trace("streamSend: \(model) http(\(status)); attempt \(attempt)/\(maxAttempts)")
                            continue
                        }
                    }
                    // Gemini exhausted/unavailable — continue the answer on a free fallback
                    // provider (Groq/Cerebras/OpenRouter/local) instead of failing.
                    for fb in currentFallbacks() where await fb.hasCredentials() {
                        do {
                            var produced = false
                            let sub = await fb.streamChat(transcript: transcript, history: history,
                                                          system: ProviderConfig.chatSystemPrompt, specs: specs)
                            for try await ev in sub {
                                try Task.checkCancellation()
                                produced = true
                                continuation.yield(ev)
                            }
                            if produced { Log.trace("fallback \(fb.label) streamed (Gemini unavailable)"); continuation.finish(); return }
                        } catch { lastError = error; continue }
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
        let data = try await performWithFallback(body: body)
        return Self.stripCodeFences(Self.extractText(from: data))
    }

    /// Plain text/JSON generation — no code framing, no JSON-schema mandate. Used by
    /// the planner and by agents synthesizing prose. Spreads across model buckets via
    /// performWithFallback (free-tier safe). Returns the model's text, fences stripped.
    func generateText(prompt: String, temperature: Double = 0.3,
                      preferredModel: String? = nil) async throws -> String {
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": temperature]
        ]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        do {
            let data = try await performWithFallback(body: body, preferredModel: preferredModel)
            return Self.stripCodeFences(Self.extractText(from: data))
        } catch {
            // Gemini exhausted/unavailable — continue on a free fallback provider.
            for fb in currentFallbacks() where await fb.hasCredentials() {
                if let text = try? await fb.generateText(prompt: prompt, temperature: temperature), !text.isEmpty {
                    Log.trace("fallback \(fb.label) answered (Gemini unavailable)")
                    return text
                }
            }
            throw error
        }
    }

    /// Vision: describe / locate things in an image. Gemini-only (the OpenAI fallbacks
    /// are text-only), used by the computer-use vision fallback.
    func generateTextWithImage(prompt: String, jpeg: Data, temperature: Double = 0.1) async throws -> String {
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": [
                ["text": prompt],
                ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
            ]]],
            "generationConfig": ["temperature": temperature]
        ]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let data = try await performWithFallback(body: body)
        return Self.stripCodeFences(Self.extractText(from: data))
    }

    /// Built only when needed (on a Gemini failure), so the normal path has zero
    /// overhead. Reads provider config from UserDefaults (no MainActor hop).
    private func currentFallbacks() -> [OpenAICompatibleClient] {
        let localOn = UserDefaults.standard.bool(forKey: "app.localModelEnabled")
        let localModel = UserDefaults.standard.string(forKey: "app.localModelName") ?? ""
        return ProviderConfig.fallbacks(includeLocal: localOn, localModel: localModel)
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

    // MARK: Networking

    // (Retry/backoff is gone — pacing + model-spread is now the RequestScheduler's
    // job, shared by both the streaming and non-streaming paths.)

    /// Try each configured model in order; if one keeps failing after retries
    /// (e.g. a model that 404s or stays overloaded for this key), fall through to
    /// the next. Throws the last error only if every model fails.
    /// One request, no internal retry — pacing/spreading is the scheduler's job.
    private func performOnce(url: URL, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Fail fast instead of hanging on the 60s default: a stalled non-streaming
        // call should bounce to the next model/provider quickly, not freeze the turn.
        // (flash/-lite JSON replies land in a few seconds; 30s is generous headroom.)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GeminiError.http(status) }
        return data
    }

    /// Non-streaming generation (chat send, planner, agents). Routes EVERY call
    /// through the same RequestScheduler as streaming, so the whole app — not just
    /// the streaming path — inherits the free-tier guarantee: a 429 paces to a free
    /// bucket and retries instead of grinding slow per-model backoff (which used to
    /// hang multi-call autonomous tasks for minutes). Only genuinely-broken models
    /// exhaust the attempt budget.
    private func performWithFallback(body: Data, preferredModel: String? = nil) async throws -> Data {
        keyRotator.update(keys: currentKeys())
        guard !keyRotator.isEmpty else { throw GeminiError.missingAPIKey }
        var lastError: Error = GeminiError.emptyResponse
        let maxAttempts = 6
        let maxQuotaWaits = 3      // brief pacing for per-minute spikes; fail fast on a hard cap
        var attempt = 0
        var quotaWaits = 0
        while attempt < maxAttempts && quotaWaits < maxQuotaWaits {
            guard let apiKey = await reserveKey(paceIfBlocked: true) else {
                quotaWaits += 1; continue   // all keys cooling — bounded, then fail fast
            }
            // Honor a caller's preferred (faster) model on the first try only; after
            // any failure, fall back to normal rotation so we still route around it.
            let firstTry = (attempt == 0 && quotaWaits == 0)
            let model = await reserveModel(preferred: firstTry ? preferredModel : nil)
            guard let url = Self.geminiURL(model: model, apiKey: apiKey) else {
                lastError = GeminiError.decodeFailed("invalid Gemini request URL")
                attempt += 1
                continue
            }
            do {
                let data = try await performOnce(url: url, body: body)
                Log.trace("gemini: \(model) ok")
                return data
            } catch let GeminiError.http(status) where status == 429 {
                lastError = GeminiError.http(status)
                quotaWaits += 1
                scheduler.penalize(model, seconds: 8)
                keyRotator.penalize(apiKey, seconds: 60)   // rotate off this key
                Log.trace("gemini: \(model) http(429); rotating key (\(quotaWaits)/\(maxQuotaWaits))")
                continue
            } catch let GeminiError.http(status) where [404, 408, 425, 500, 502, 503, 504].contains(status) {
                lastError = GeminiError.http(status)
                attempt += 1
                Log.trace("gemini: \(model) http(\(status)); attempt \(attempt)/\(maxAttempts)")
                continue
            } catch {
                lastError = error
                attempt += 1
                Log.trace("gemini: \(model) error (\(error)); attempt \(attempt)/\(maxAttempts)")
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
        - User: \(context.username)\(context.ambientLines)
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

    SYSTEM CONTEXT tells you what the user is looking at right now — the active app, \
    window, focused field, and any selected text. Use it to resolve words like \
    "this", "that", "here", "her", or "the selection" without asking what they mean. \
    If they say "summarize this" and there's selected text, summarize that text; if \
    not, read the screen. When they reference the thing in front of them, act on the \
    SYSTEM CONTEXT — don't make them describe it.
    """
}
