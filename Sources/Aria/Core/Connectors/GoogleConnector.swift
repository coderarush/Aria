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
        "https://www.googleapis.com/auth/calendar.readonly"
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

    /// Fetch recent Gmail message metadata (From/Subject + snippet). Lists IDs,
    /// then fetches each in `metadata` format. `accessToken` must be valid.
    func recentGmail(accessToken: String, maxResults: Int = 5,
                     session: URLSession = .shared) async throws -> [GmailMessageSummary] {
        var listComps = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        listComps.queryItems = [URLQueryItem(name: "maxResults", value: String(maxResults))]
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

    /// Fetch upcoming Calendar events from the primary calendar.
    func upcomingEvents(accessToken: String, maxResults: Int = 5,
                        now: Date = Date(),
                        session: URLSession = .shared) async throws -> [CalendarEvent] {
        var comps = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let iso = ISO8601DateFormatter().string(from: now)
        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: iso),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        let data = try await authorizedGET(comps.url!, accessToken: accessToken,
                                          session: session)
        return Self.parseCalendarEvents(data)
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
}
