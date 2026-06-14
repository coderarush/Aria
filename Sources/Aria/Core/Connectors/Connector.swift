import Foundation

/// Identity of a third-party account Aria can connect to. The set is fixed
/// (Google, Notion, Slack); each case carries its OAuth endpoints and scopes.
enum ConnectorID: String, CaseIterable, Sendable, Codable {
    case google
    case notion
    case slack
}

/// Describes one OAuth-backed provider: the endpoints, scopes, and the
/// Keychain/UserDefaults keys where the user-supplied client ID lives.
///
/// No secrets are compiled in. The client ID is supplied by the user (each
/// install registers its own OAuth app) and read from the Keychain first, then
/// UserDefaults as a fallback. A missing client ID is a clean, surfaced state
/// (`isConfigured == false`) — never a crash.
protocol ConnectorProvider: Sendable {
    var id: ConnectorID { get }
    var displayName: String { get }
    var scopes: [String] { get }
    var authEndpoint: String { get }
    var tokenEndpoint: String { get }
    /// Extra auth-request parameters (e.g. Google's `access_type=offline`).
    var extraAuthParameters: [String: String] { get }
    /// The Keychain account key under which the user's client ID is stored.
    var clientIDKeychainAccount: String { get }
    /// The UserDefaults key checked if the Keychain has no client ID.
    var clientIDDefaultsKey: String { get }
    /// Whether this provider is a confidential client that signs token requests
    /// with a client secret (Notion, Slack). Google's native installed-app PKCE
    /// flow sends no secret, so this is `false` for Google.
    var usesClientSecret: Bool { get }
    /// The Keychain account key under which the user's client secret is stored.
    var clientSecretKeychainAccount: String { get }
}

extension ConnectorProvider {
    var extraAuthParameters: [String: String] { [:] }
    var clientIDKeychainAccount: String { "connector_\(id.rawValue)_client_id" }
    var clientIDDefaultsKey: String { "connector.\(id.rawValue).clientID" }
    /// Default: PKCE-only, no secret. Confidential providers override to `true`.
    var usesClientSecret: Bool { false }
    var clientSecretKeychainAccount: String { "connector_\(id.rawValue)_client_secret" }

    /// Resolve the user-supplied OAuth client ID, or nil if not configured.
    /// Keychain wins; UserDefaults is the fallback for non-secret IDs that a
    /// user may have pasted into settings. Never throws, never crashes.
    func resolvedClientID(
        keychainRead: (String) -> String? = { KeychainManager.read(account: $0) },
        defaults: UserDefaults = .standard
    ) -> String? {
        if let k = keychainRead(clientIDKeychainAccount),
           !k.trimmingCharacters(in: .whitespaces).isEmpty {
            return k
        }
        if let d = defaults.string(forKey: clientIDDefaultsKey),
           !d.trimmingCharacters(in: .whitespaces).isEmpty {
            return d
        }
        return nil
    }

    /// Resolve the user-supplied OAuth client secret, or nil. Secrets live ONLY
    /// in the Keychain (never UserDefaults) and only for confidential providers;
    /// PKCE-only providers (Google) always resolve to nil so no secret is sent.
    /// Never throws, never crashes, never logged.
    func resolvedClientSecret(
        keychainRead: (String) -> String? = { KeychainManager.read(account: $0) }
    ) -> String? {
        guard usesClientSecret else { return nil }
        guard let s = keychainRead(clientSecretKeychainAccount),
              !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    var isConfigured: Bool { resolvedClientID() != nil }

    /// Build an `OAuth2.AuthConfig` from this provider + a resolved client ID,
    /// threading the stored client secret for confidential providers (nil for
    /// Google's PKCE-only flow, so it is never sent on the wire).
    func authConfig(clientID: String) -> OAuth2.AuthConfig {
        OAuth2.AuthConfig(clientID: clientID,
                          clientSecret: resolvedClientSecret(),
                          authEndpoint: authEndpoint,
                          tokenEndpoint: tokenEndpoint,
                          scopes: scopes,
                          extraAuthParameters: extraAuthParameters)
    }
}

/// The registry of known providers, keyed by `ConnectorID`. Google is fully
/// implemented; Notion and Slack carry their real endpoints so they can be
/// wired up later without touching this file.
enum Connectors {
    static func provider(for id: ConnectorID) -> ConnectorProvider {
        switch id {
        case .google: return GoogleConnector()
        case .notion: return NotionConnector()
        case .slack:  return SlackConnector()
        }
    }

    static var all: [ConnectorProvider] { ConnectorID.allCases.map(provider) }
}

/// Notion endpoints (OAuth2). Scope set is implicit in Notion's integration
/// settings, so `scopes` is empty here. Endpoints kept accurate for later use.
///
/// Adds thin authorized helpers (search + append) that mirror GoogleConnector's
/// transport pattern: an authorized POST/PATCH with a JSON body and bearer token,
/// pure request-body builders + response parsers factored out for testing. The
/// Notion REST API lives at `api.notion.com/v1` and requires the version header
/// `Notion-Version: 2022-06-28` on every call. Tokens are never logged.
struct NotionConnector: ConnectorProvider {
    let id: ConnectorID = .notion
    let displayName = "Notion"
    let scopes: [String] = []
    let authEndpoint = "https://api.notion.com/v1/oauth/authorize"
    let tokenEndpoint = "https://api.notion.com/v1/oauth/token"
    var extraAuthParameters: [String: String] { ["owner": "user"] }
    /// Notion is a confidential client — its token endpoint requires the secret.
    let usesClientSecret = true

    /// The version header Notion's REST API requires on every request.
    static let apiVersion = "2022-06-28"

    // MARK: - Authorized operations (thin)

    /// A compact Notion search hit — a page or database the query matched.
    struct SearchHit: Sendable, Equatable {
        enum Kind: String, Sendable { case page, database, other }
        let id: String
        let kind: Kind
        let title: String
        let url: String
    }

    /// Search the user's Notion workspace for pages and databases matching
    /// `query` (read). An empty query returns the most recently edited objects.
    /// `accessToken` must be valid.
    func search(query: String, accessToken: String, pageSize: Int = 10,
                session: URLSession = .shared) async throws -> [SearchHit] {
        let url = URL(string: "https://api.notion.com/v1/search")!
        let payload = Self.searchBody(query: query, pageSize: pageSize)
        let data = try await authorizedJSON(url, method: "POST", body: payload,
                                            accessToken: accessToken, session: session)
        return Self.parseSearchResults(data)
    }

    /// Append a paragraph of text to a Notion page by id (write, reversible-ish —
    /// a block can be deleted). Returns the parent page/block id Notion echoes
    /// back. `accessToken` must be valid.
    func appendText(pageID: String, text: String, accessToken: String,
                    session: URLSession = .shared) async throws -> String {
        let url = URL(string: "https://api.notion.com/v1/blocks/\(pageID)/children")!
        let payload = Self.appendBody(text: text)
        let data = try await authorizedJSON(url, method: "PATCH", body: payload,
                                            accessToken: accessToken, session: session)
        guard let id = Self.parseAppendedParentID(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return id
    }

    // MARK: - Pure request-body builders (testable)

    /// The JSON body for `POST /v1/search`. An empty/whitespace query is omitted
    /// so Notion returns the most recently edited objects rather than nothing.
    static func searchBody(query: String, pageSize: Int = 10) -> [String: Any] {
        var body: [String: Any] = ["page_size": max(1, min(pageSize, 100))]
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { body["query"] = q }
        return body
    }

    /// The JSON body for `PATCH /v1/blocks/{id}/children` — one paragraph block
    /// holding the text as a single rich-text run.
    static func appendBody(text: String) -> [String: Any] {
        [
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            ["type": "text", "text": ["content": text]]
                        ]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Pure response parsers (testable)

    /// Parse `POST /v1/search` results into compact hits. Titles live in
    /// different places for pages (a title-typed property) vs databases (a
    /// top-level `title` rich-text array); both are handled, missing titles
    /// degrade to "(untitled)".
    static func parseSearchResults(_ data: Data) -> [SearchHit] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let objectType = (item["object"] as? String) ?? ""
            let kind: SearchHit.Kind = objectType == "page" ? .page
                : objectType == "database" ? .database : .other
            let url = (item["url"] as? String) ?? ""
            let title = extractTitle(from: item, kind: kind)
            return SearchHit(id: id, kind: kind, title: title, url: url)
        }
    }

    /// Pull a human-readable title out of a search result. Databases carry a
    /// top-level `title` rich-text array; pages carry it inside the title-typed
    /// entry of `properties`.
    static func extractTitle(from item: [String: Any], kind: SearchHit.Kind) -> String {
        if kind == .database, let rt = item["title"] as? [[String: Any]] {
            let joined = plainText(from: rt)
            if !joined.isEmpty { return joined }
        }
        if let props = item["properties"] as? [String: Any] {
            for (_, value) in props {
                guard let prop = value as? [String: Any],
                      (prop["type"] as? String) == "title",
                      let rt = prop["title"] as? [[String: Any]] else { continue }
                let joined = plainText(from: rt)
                if !joined.isEmpty { return joined }
            }
        }
        return "(untitled)"
    }

    /// Concatenate the `plain_text` of a Notion rich-text array.
    static func plainText(from richText: [[String: Any]]) -> String {
        richText.compactMap { $0["plain_text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A successful append echoes the children list; we return the request's
    /// parent block id when present, else the first appended child's id, so the
    /// caller has something to confirm with.
    static func parseAppendedParentID(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let results = obj["results"] as? [[String: Any]],
           let first = results.first, let id = first["id"] as? String {
            return id
        }
        return obj["id"] as? String
    }

    // MARK: - Display formatting (pure / testable)

    /// Render search hits into the user-facing text block the tool returns.
    static func formatSearch(_ hits: [SearchHit]) -> String {
        guard !hits.isEmpty else { return "No matching Notion pages or databases." }
        let lines = hits.map { hit -> String in
            "• \(hit.title) [\(hit.kind.rawValue)]"
        }
        return "Notion results:\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Transport (thin)

    /// Authorized POST/PATCH with a JSON body, bearer token, and Notion's
    /// required version header. Notion returns 200 on success. Body is built by
    /// the pure `*Body` builders above so it stays testable.
    private func authorizedJSON(_ url: URL, method: String, body: [String: Any],
                                accessToken: String,
                                session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw OAuth2.OAuth2Error.tokenExchangeFailed(status)
        }
        return data
    }
}

/// Slack endpoints (OAuth v2). Read-oriented default scopes.
///
/// Adds thin authorized helpers (recent messages + send) over the Slack Web API
/// at `slack.com/api`. Slack differs from Google/Notion in one important way:
/// a call can return HTTP 200 with `{"ok": false, "error": "..."}` for a logical
/// failure (bad channel, missing scope), so the transport checks the `ok` field,
/// not just the status code. Pure request shaping + response parsing are factored
/// out for testing; tokens are never logged.
struct SlackConnector: ConnectorProvider {
    let id: ConnectorID = .slack
    let displayName = "Slack"
    let scopes = ["channels:read", "channels:history", "chat:write", "users:read"]
    let authEndpoint = "https://slack.com/oauth/v2/authorize"
    let tokenEndpoint = "https://slack.com/api/oauth.v2.access"
    /// Slack's `oauth.v2.access` requires the client secret on the exchange.
    let usesClientSecret = true

    // MARK: - Authorized operations (thin)

    /// A compact Slack message — author id + text. Slack's `conversations.history`
    /// returns user ids (not display names); resolving those to names needs an
    /// extra `users.info` round-trip per id, which we skip to stay thin.
    struct SlackMessage: Sendable, Equatable {
        let user: String
        let text: String
        let ts: String
    }

    /// The outcome of a Slack send — the channel and server-assigned message
    /// timestamp (`ts`), which is Slack's message id.
    struct SlackSendResult: Sendable, Equatable {
        let channel: String
        let ts: String
    }

    /// Fetch recent messages from a channel (read). `channel` is a channel id
    /// (e.g. "C0123ABCD"). `accessToken` must be valid.
    func recentMessages(channel: String, limit: Int = 10, accessToken: String,
                        session: URLSession = .shared) async throws -> [SlackMessage] {
        var comps = URLComponents(string: "https://slack.com/api/conversations.history")!
        comps.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
        ]
        let data = try await authorizedGET(comps.url!, accessToken: accessToken,
                                           session: session)
        return Self.parseHistory(data)
    }

    /// Post a message to a channel (write — EXTERNAL COMMS, the calling tool
    /// gates). `channel` is a channel id or name. Returns the channel + ts.
    /// `accessToken` must be valid.
    func sendMessage(channel: String, text: String, accessToken: String,
                     session: URLSession = .shared) async throws -> SlackSendResult {
        let url = URL(string: "https://slack.com/api/chat.postMessage")!
        let payload = Self.postMessageBody(channel: channel, text: text)
        let data = try await authorizedJSON(url, method: "POST", body: payload,
                                            accessToken: accessToken, session: session)
        guard let result = Self.parseSendResult(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return result
    }

    // MARK: - Pure request-body builders (testable)

    /// The JSON body for `chat.postMessage`: `{"channel": ..., "text": ...}`.
    static func postMessageBody(channel: String, text: String) -> [String: Any] {
        ["channel": channel, "text": text]
    }

    // MARK: - Pure response parsers (testable)

    /// Parse `conversations.history` into compact messages. Returns [] when Slack
    /// reports `ok == false` or the shape is unexpected. Sub-types (channel join
    /// notices, etc.) carry a `subtype` and an empty `user`; we keep only real
    /// user messages with non-empty text.
    static func parseHistory(_ data: Data) -> [SlackMessage] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let messages = obj["messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { m in
            let text = (m["text"] as? String) ?? ""
            guard !text.isEmpty else { return nil }
            let user = (m["user"] as? String) ?? (m["bot_id"] as? String) ?? "(unknown)"
            let ts = (m["ts"] as? String) ?? ""
            return SlackMessage(user: user, text: text, ts: ts)
        }
    }

    /// Parse a `chat.postMessage` response. Returns nil when `ok == false` or the
    /// channel/ts are missing, so the caller surfaces a clean failure.
    static func parseSendResult(_ data: Data) -> SlackSendResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let channel = obj["channel"] as? String,
              let ts = obj["ts"] as? String else { return nil }
        return SlackSendResult(channel: channel, ts: ts)
    }

    // MARK: - Display formatting (pure / testable)

    /// Render recent Slack messages into the user-facing text block.
    static func formatMessages(_ messages: [SlackMessage]) -> String {
        guard !messages.isEmpty else { return "No recent Slack messages in that channel." }
        let lines = messages.map { m -> String in
            "• \(m.user): \(m.text)"
        }
        return "Recent Slack messages:\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Transport (thin)

    /// Authorized GET with a bearer token. Treats a non-200 status OR a Slack
    /// `ok == false` body as an error so logical failures don't look like empty
    /// reads. Returns the raw body for the pure parsers above.
    private func authorizedGET(_ url: URL, accessToken: String,
                               session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OAuth2.OAuth2Error.tokenExchangeFailed(status) }
        try Self.throwIfNotOK(data)
        return data
    }

    /// Authorized POST with a JSON body and bearer token. Same `ok`-aware error
    /// handling as the GET path.
    private func authorizedJSON(_ url: URL, method: String, body: [String: Any],
                                accessToken: String,
                                session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OAuth2.OAuth2Error.tokenExchangeFailed(status) }
        try Self.throwIfNotOK(data)
        return data
    }

    /// Slack returns HTTP 200 even for logical errors, signalled by `ok == false`.
    /// Throw on those so a bad channel / missing scope is a real error, not a
    /// silently empty result.
    static func throwIfNotOK(_ data: Data) throws {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw OAuth2.OAuth2Error.malformedTokenResponse }
        if (obj["ok"] as? Bool) == false {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
    }
}
