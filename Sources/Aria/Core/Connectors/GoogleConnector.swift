import Foundation

/// Google OAuth provider — Gmail + Calendar read scopes. Conforms to
/// `ConnectorProvider` (endpoints/scopes) and adds thin authorized-GET helpers
/// that the autonomy layer can call once a token is stored.
///
/// Client ID is user-supplied (Keychain `connector_google_client_id`, falling
/// back to UserDefaults `connector.google.clientID`). No secret is compiled in;
/// the loopback-redirect + PKCE flow is exactly the "installed app" pattern
/// Google documents for native apps, which need no client secret.
struct GoogleConnector: ConnectorProvider {
    let id: ConnectorID = .google
    let displayName = "Google"
    let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",        // gmail_send
        "https://www.googleapis.com/auth/gmail.compose",     // gmail_draft
        "https://www.googleapis.com/auth/calendar.events",   // gcal_create
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/drive.readonly",    // drive_search + drive_read
        "https://www.googleapis.com/auth/drive.file"         // drive_create (files this app touches)
    ]
    let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    let tokenEndpoint = "https://oauth2.googleapis.com/token"
    /// Google only returns a refresh_token when `access_type=offline` and (for a
    /// re-consent) `prompt=consent` are present — without these a long-lived
    /// connection silently breaks after the first hour.
    var extraAuthParameters: [String: String] {
        ["access_type": "offline", "prompt": "consent"]
    }

    // MARK: - Authorized reads (thin)

    /// A compact summary of a recent Gmail message (metadata only — we request
    /// the `metadata` format, never bodies).
    struct GmailMessageSummary: Sendable, Equatable {
        let id: String
        let from: String
        let subject: String
        let snippet: String
    }

    /// A compact upcoming Calendar event.
    struct CalendarEvent: Sendable, Equatable {
        let summary: String
        let start: String
    }

    /// A compact Drive file match (search result row).
    struct DriveFile: Sendable, Equatable {
        let id: String
        let name: String
        let mimeType: String
    }

    /// The outcome of reading a Drive file: either text we could extract, or a
    /// clean note explaining we can't read this type (binary, image, etc.).
    enum DriveReadResult: Sendable, Equatable {
        case text(name: String, content: String)
        case unreadable(name: String, mimeType: String)
    }

    /// Fetch recent Gmail message metadata (From/Subject + snippet). Lists IDs,
    /// then fetches each in `metadata` format. `accessToken` must be valid. An
    /// optional `query` is passed straight to Gmail's `q` search operator (e.g.
    /// "from:boss is:unread"); nil/empty means "most recent".
    func recentGmail(accessToken: String, maxResults: Int = 5,
                     query: String? = nil,
                     session: URLSession = .shared) async throws -> [GmailMessageSummary] {
        var listComps = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        var listItems = [URLQueryItem(name: "maxResults", value: String(maxResults))]
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            listItems.append(URLQueryItem(name: "q", value: q))
        }
        listComps.queryItems = listItems
        let listData = try await authorizedGET(listComps.url!, accessToken: accessToken,
                                               session: session)
        guard let listObj = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let messages = listObj["messages"] as? [[String: Any]] else { return [] }

        var out: [GmailMessageSummary] = []
        for m in messages.prefix(maxResults) {
            guard let mid = m["id"] as? String else { continue }
            var comps = URLComponents(
                string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(mid)")!
            comps.queryItems = [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Subject")
            ]
            let data = try await authorizedGET(comps.url!, accessToken: accessToken,
                                              session: session)
            if let summary = Self.parseGmailMessage(data) { out.append(summary) }
        }
        return out
    }

    /// Fetch upcoming Calendar events from the primary calendar. An optional
    /// `within` window bounds the search with `timeMax` (e.g. 7 days out); nil
    /// means unbounded-forward (the original behavior).
    func upcomingEvents(accessToken: String, maxResults: Int = 5,
                        now: Date = Date(), within: TimeInterval? = nil,
                        session: URLSession = .shared) async throws -> [CalendarEvent] {
        var comps = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let formatter = ISO8601DateFormatter()
        var items = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: now)),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        if let within {
            items.append(URLQueryItem(name: "timeMax",
                                      value: formatter.string(from: now.addingTimeInterval(within))))
        }
        comps.queryItems = items
        let data = try await authorizedGET(comps.url!, accessToken: accessToken,
                                          session: session)
        return Self.parseCalendarEvents(data)
    }

    // MARK: - Authorized writes (thin)

    /// The outcome of a Gmail write (send or draft) — the server-assigned id so
    /// callers can confirm or follow up. `kind` distinguishes a sent message
    /// from a created (unsent) draft.
    struct GmailWriteResult: Sendable, Equatable {
        enum Kind: String, Sendable { case message, draft }
        let kind: Kind
        let id: String
    }

    /// Send an email through the connected Gmail account (`messages.send` with a
    /// base64url RFC822 `raw` body). EXTERNAL COMMS — the tool that calls this is
    /// gated under high autonomy. Returns the sent message's id.
    func sendGmail(to: String, subject: String, body: String,
                   accessToken: String,
                   session: URLSession = .shared) async throws -> GmailWriteResult {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        let payload = Self.gmailSendBody(to: to, subject: subject, body: body)
        let data = try await authorizedJSON(url, method: "POST", body: payload,
                                            accessToken: accessToken, session: session)
        guard let id = Self.parseGmailWriteID(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return GmailWriteResult(kind: .message, id: id)
    }

    /// Create a Gmail draft (does NOT send). Reversible — the tool that calls
    /// this does not gate. Returns the created draft's id.
    func createDraft(to: String, subject: String, body: String,
                     accessToken: String,
                     session: URLSession = .shared) async throws -> GmailWriteResult {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts")!
        let payload = Self.gmailDraftBody(to: to, subject: subject, body: body)
        let data = try await authorizedJSON(url, method: "POST", body: payload,
                                            accessToken: accessToken, session: session)
        guard let id = Self.parseDraftID(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return GmailWriteResult(kind: .draft, id: id)
    }

    /// Create an event on the primary Calendar. Reversible (an event can be
    /// deleted) — the tool that calls this does not gate. `start`/`end` are
    /// RFC3339 timestamps (e.g. "2026-06-20T15:00:00Z"). Returns the new
    /// event id.
    func createEvent(title: String, start: String, end: String,
                     accessToken: String,
                     session: URLSession = .shared) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let payload = Self.calendarEventBody(title: title, start: start, end: end)
        let data = try await authorizedJSON(url, method: "POST", body: payload,
                                            accessToken: accessToken, session: session)
        guard let id = Self.parseCalendarEventID(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return id
    }

    // MARK: - Authorized Drive (search / read / create, thin)

    /// Search Drive for files matching a free-text term. The user's `query` is
    /// wrapped into Drive's `name contains '…'` operator and trashed files are
    /// excluded. Returns up to `maxResults` compact matches; empty on no hits.
    func searchDriveFiles(query: String, accessToken: String, maxResults: Int = 10,
                          session: URLSession = .shared) async throws -> [DriveFile] {
        let data = try await authorizedGET(Self.driveSearchURL(query: query, maxResults: maxResults),
                                           accessToken: accessToken, session: session)
        return Self.parseDriveFileList(data)
    }

    /// Read a Drive file by id. Google-native docs (Docs/Sheets/Slides) are
    /// exported to `text/plain`; everything else is fetched with `?alt=media`.
    /// Binary/unknown types come back as `.unreadable` with a clean note rather
    /// than dumping bytes. We fetch metadata first to learn the name + mimeType.
    func readDriveFile(id: String, accessToken: String,
                       session: URLSession = .shared) async throws -> DriveReadResult {
        let meta = try await authorizedGET(Self.driveMetadataURL(id: id),
                                           accessToken: accessToken, session: session)
        let (name, mimeType) = Self.parseDriveFileMeta(meta)
        // A Google-native doc can't be downloaded directly — it must be exported.
        if Self.isGoogleNativeTextDoc(mimeType) {
            let data = try await authorizedGET(Self.driveExportURL(id: id, mimeType: "text/plain"),
                                               accessToken: accessToken, session: session)
            return .text(name: name, content: String(decoding: data, as: UTF8.self))
        }
        // Plain text-ish files download with alt=media; binary types we decline.
        guard Self.isReadableMediaType(mimeType) else {
            return .unreadable(name: name, mimeType: mimeType)
        }
        let data = try await authorizedGET(Self.driveMediaURL(id: id),
                                           accessToken: accessToken, session: session)
        return .text(name: name, content: String(decoding: data, as: UTF8.self))
    }

    /// Create a plain-text file in Drive via a multipart "simple upload". Returns
    /// the new file id. Reversible-ish (the file can be trashed), so the tool that
    /// calls this does not gate.
    func createDriveFile(name: String, content: String, accessToken: String,
                         session: URLSession = .shared) async throws -> String {
        let (body, contentType) = Self.driveMultipartBody(name: name, content: content)
        let data = try await authorizedUpload(Self.driveUploadURL(), method: "POST",
                                              body: body, contentType: contentType,
                                              accessToken: accessToken, session: session)
        guard let id = Self.parseDriveFileID(data) else {
            throw OAuth2.OAuth2Error.malformedTokenResponse
        }
        return id
    }

    // MARK: - Authorized deletes (undo support, thin)

    /// Delete a Gmail draft by id (`drafts.delete`) — the inverse of
    /// `createDraft`, used by Undo. Throws on a non-success status so the undo
    /// path can report a clean failure.
    func deleteDraft(id: String, accessToken: String,
                     session: URLSession = .shared) async throws {
        try await authorizedDELETE(Self.draftDeleteURL(id: id),
                                   accessToken: accessToken, session: session)
    }

    /// Delete a Calendar event by id from the primary calendar
    /// (`events.delete`) — the inverse of `createEvent`, used by Undo.
    func deleteEvent(id: String, accessToken: String,
                     session: URLSession = .shared) async throws {
        try await authorizedDELETE(Self.eventDeleteURL(id: id),
                                   accessToken: accessToken, session: session)
    }

    // MARK: - Pure DELETE-URL builders (testable)

    /// `DELETE …/users/me/drafts/{id}` — the draft id is path-percent-encoded so
    /// an unusual id can't break the URL.
    static func draftDeleteURL(id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts/\(encoded)")!
    }

    /// `DELETE …/calendars/primary/events/{id}` — the event id is
    /// path-percent-encoded.
    static func eventDeleteURL(id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encoded)")!
    }

    // MARK: - Pure Drive URL builders (testable)

    /// Drive API v3 base.
    static let driveBase = "https://www.googleapis.com/drive/v3"

    /// `GET /files?q=name contains '<query>' and trashed=false` — the user term is
    /// single-quote-escaped (Drive's query language doubles a `'` to escape) and
    /// the whole thing is percent-encoded by URLComponents. We project just the
    /// fields the parser needs.
    static func driveSearchURL(query: String, maxResults: Int = 10) -> URL {
        let escaped = query.replacingOccurrences(of: "'", with: "\\'")
        var comps = URLComponents(string: "\(driveBase)/files")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "name contains '\(escaped)' and trashed = false"),
            URLQueryItem(name: "pageSize", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType)")
        ]
        return comps.url!
    }

    /// `GET /files/{id}?fields=name,mimeType` — file id is path-percent-encoded so
    /// an unusual id can't break the URL.
    static func driveMetadataURL(id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var comps = URLComponents(string: "\(driveBase)/files/\(encoded)")!
        comps.queryItems = [URLQueryItem(name: "fields", value: "name,mimeType")]
        return comps.url!
    }

    /// `GET /files/{id}/export?mimeType=…` — for Google-native docs (Docs/Sheets/
    /// Slides) which can't be downloaded directly. id is path-percent-encoded.
    static func driveExportURL(id: String, mimeType: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var comps = URLComponents(string: "\(driveBase)/files/\(encoded)/export")!
        comps.queryItems = [URLQueryItem(name: "mimeType", value: mimeType)]
        return comps.url!
    }

    /// `GET /files/{id}?alt=media` — raw download for non-native files.
    static func driveMediaURL(id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var comps = URLComponents(string: "\(driveBase)/files/\(encoded)")!
        comps.queryItems = [URLQueryItem(name: "alt", value: "media")]
        return comps.url!
    }

    /// `POST …/upload/drive/v3/files?uploadType=multipart` — the multipart simple
    /// upload endpoint (note the `/upload` path prefix, distinct from the metadata
    /// API base).
    static func driveUploadURL() -> URL {
        var comps = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")!
        comps.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
        return comps.url!
    }

    // MARK: - Drive MIME-type classification (pure / testable)

    /// Google-native docs we can export to plain text.
    static func isGoogleNativeTextDoc(_ mimeType: String) -> Bool {
        [
            "application/vnd.google-apps.document",
            "application/vnd.google-apps.spreadsheet",
            "application/vnd.google-apps.presentation"
        ].contains(mimeType)
    }

    /// Non-native types we'll attempt to read as UTF-8 text via alt=media. Other
    /// google-apps types (folders, forms) and binaries are declined.
    static func isReadableMediaType(_ mimeType: String) -> Bool {
        if mimeType.hasPrefix("text/") { return true }
        return [
            "application/json",
            "application/xml",
            "application/javascript",
            "application/rtf"
        ].contains(mimeType)
    }

    // MARK: - Pure Drive multipart body (testable)

    /// A multipart/related "simple upload" body: a JSON metadata part (the file
    /// name) + a text/plain media part (the content). Returns the body bytes and
    /// the `Content-Type` header value carrying the boundary.
    static func driveMultipartBody(name: String, content: String,
                                   boundary: String = "aria-drive-boundary") -> (Data, String) {
        let metadata = (try? JSONSerialization.data(
            withJSONObject: ["name": name])).flatMap { String(data: $0, encoding: .utf8) }
            ?? "{\"name\":\"\(name)\"}"
        let parts = [
            "--\(boundary)",
            "Content-Type: application/json; charset=UTF-8",
            "",
            metadata,
            "--\(boundary)",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            content,
            "--\(boundary)--",
            ""
        ].joined(separator: "\r\n")
        return (Data(parts.utf8), "multipart/related; boundary=\(boundary)")
    }

    // MARK: - Pure Drive response parsers (testable)

    /// A `files.list` response: `{"files":[{"id","name","mimeType"},…]}`.
    static func parseDriveFileList(_ data: Data) -> [DriveFile] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { return [] }
        return files.compactMap { f in
            guard let id = f["id"] as? String, let name = f["name"] as? String else { return nil }
            return DriveFile(id: id, name: name, mimeType: (f["mimeType"] as? String) ?? "")
        }
    }

    /// A file-metadata response: `{"name":…,"mimeType":…}`. Missing fields fall
    /// back to safe defaults so a read never crashes.
    static func parseDriveFileMeta(_ data: Data) -> (name: String, mimeType: String) {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((obj?["name"] as? String) ?? "(untitled)",
                (obj?["mimeType"] as? String) ?? "")
    }

    /// A `files.create` response: top-level `{"id": "..."}` is the new file id.
    static func parseDriveFileID(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["id"] as? String
    }

    // MARK: - Drive display formatting (pure / testable)

    /// Render Drive search matches into the user-facing text block a tool returns.
    static func formatDriveFiles(_ files: [DriveFile]) -> String {
        guard !files.isEmpty else { return "No matching Google Drive files found." }
        let lines = files.map { "• \($0.name)  [id: \($0.id)]" }
        return "Google Drive matches:\n\(lines.joined(separator: "\n"))"
    }

    /// Render a Drive read result into a user-facing block — the text, or a clean
    /// "can't read this type" note.
    static func formatDriveRead(_ result: DriveReadResult) -> String {
        switch result {
        case let .text(name, content):
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "\"\(name)\" is empty."
                : "\(name):\n\(trimmed)"
        case let .unreadable(name, mimeType):
            return "I can't read \"\(name)\" as text (type \(mimeType.isEmpty ? "unknown" : mimeType)). I can find and link it, but reading this file type isn't supported yet."
        }
    }

    // MARK: - Pure request-body builders (testable)

    /// Encode an address/subject/body as a base64url RFC822 message (no padding),
    /// the exact `raw` shape Gmail's `messages.send` / `drafts.create` require.
    static func gmailRawMessage(to: String, subject: String, body: String) -> String {
        // RFC822 headers + blank line + body. CRLF line endings per the spec.
        let mime = [
            "To: \(to)",
            "Subject: \(subject)",
            "Content-Type: text/plain; charset=\"UTF-8\"",
            "MIME-Version: 1.0",
            "",
            body
        ].joined(separator: "\r\n")
        return base64url(Data(mime.utf8))
    }

    /// The JSON body for `messages.send`: `{"raw": "<base64url RFC822>"}`.
    static func gmailSendBody(to: String, subject: String, body: String) -> [String: Any] {
        ["raw": gmailRawMessage(to: to, subject: subject, body: body)]
    }

    /// The JSON body for `drafts.create`: `{"message": {"raw": "…"}}`.
    static func gmailDraftBody(to: String, subject: String, body: String) -> [String: Any] {
        ["message": ["raw": gmailRawMessage(to: to, subject: subject, body: body)]]
    }

    /// The JSON body for Calendar `events.insert` — timed event on the primary
    /// calendar, start/end as RFC3339 `dateTime`s.
    static func calendarEventBody(title: String, start: String, end: String) -> [String: Any] {
        [
            "summary": title,
            "start": ["dateTime": start],
            "end": ["dateTime": end]
        ]
    }

    /// base64url with no `=` padding (RFC 4648 §5) — Gmail rejects standard
    /// base64 here.
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Pure write-response parsers (testable)

    /// A sent/inserted Gmail message returns `{"id": "...", ...}`.
    static func parseGmailWriteID(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["id"] as? String
    }

    /// A created draft returns `{"id": "...", "message": {...}}` — the draft id is
    /// the top-level `id`.
    static func parseDraftID(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["id"] as? String
    }

    /// An inserted Calendar event returns `{"id": "...", ...}`.
    static func parseCalendarEventID(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["id"] as? String
    }

    // MARK: - Pure response parsers (testable)

    static func parseGmailMessage(_ data: Data) -> GmailMessageSummary? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else { return nil }
        let snippet = (obj["snippet"] as? String) ?? ""
        var from = "", subject = ""
        if let payload = obj["payload"] as? [String: Any],
           let headers = payload["headers"] as? [[String: Any]] {
            for h in headers {
                guard let name = h["name"] as? String, let value = h["value"] as? String
                else { continue }
                if name.caseInsensitiveCompare("From") == .orderedSame { from = value }
                if name.caseInsensitiveCompare("Subject") == .orderedSame { subject = value }
            }
        }
        return GmailMessageSummary(id: id, from: from, subject: subject, snippet: snippet)
    }

    static func parseCalendarEvents(_ data: Data) -> [CalendarEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let summary = (item["summary"] as? String) ?? "(no title)"
            let start = item["start"] as? [String: Any]
            let when = (start?["dateTime"] as? String) ?? (start?["date"] as? String) ?? ""
            return CalendarEvent(summary: summary, start: when)
        }
    }

    // MARK: - Display formatting (pure / testable)

    /// Render Gmail summaries into the user-facing text block a tool returns.
    /// Empty input yields a clean "no messages" line rather than an empty body.
    static func formatGmail(_ messages: [GmailMessageSummary]) -> String {
        guard !messages.isEmpty else { return "No recent Gmail messages found." }
        let lines = messages.map { m -> String in
            let from = m.from.isEmpty ? "(unknown sender)" : m.from
            let subject = m.subject.isEmpty ? "(no subject)" : m.subject
            var line = "• \(subject) — from \(from)"
            let snippet = m.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty { line += "\n  \(snippet)" }
            return line
        }
        return "Recent Gmail:\n\(lines.joined(separator: "\n"))"
    }

    /// Render upcoming Calendar events into the user-facing text block.
    static func formatEvents(_ events: [CalendarEvent]) -> String {
        guard !events.isEmpty else { return "No upcoming Google Calendar events." }
        let lines = events.map { e -> String in
            let when = e.start.isEmpty ? "(no time)" : e.start
            return "• \(when) — \(e.summary)"
        }
        return "Upcoming Google Calendar events:\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Transport (thin)

    private func authorizedGET(_ url: URL, accessToken: String,
                               session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OAuth2.OAuth2Error.tokenExchangeFailed(status) }
        return data
    }

    /// Authorized POST/PATCH with a JSON body and bearer token. Accepts 200 and
    /// 201 (Gmail send/draft return 200; Calendar insert returns 200, drafts may
    /// return 200/201 across API versions). The body is built purely by the
    /// `*Body` builders above so it stays testable.
    private func authorizedJSON(_ url: URL, method: String, body: [String: Any],
                                accessToken: String,
                                session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw OAuth2.OAuth2Error.tokenExchangeFailed(status)
        }
        return data
    }

    /// Authorized upload with a raw body + explicit Content-Type (used for Drive's
    /// multipart simple upload, whose body isn't JSON). Accepts 200 and 201 (Drive
    /// `files.create` returns 200).
    private func authorizedUpload(_ url: URL, method: String, body: Data,
                                  contentType: String, accessToken: String,
                                  session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw OAuth2.OAuth2Error.tokenExchangeFailed(status)
        }
        return data
    }

    /// Authorized DELETE with a bearer token and no body. Gmail `drafts.delete`
    /// and Calendar `events.delete` return 204 No Content on success (200 is
    /// tolerated across API versions); any other status throws so the undo path
    /// reports a clean failure.
    private func authorizedDELETE(_ url: URL, accessToken: String,
                                  session: URLSession) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 || status == 200 else {
            throw OAuth2.OAuth2Error.tokenExchangeFailed(status)
        }
    }
}
