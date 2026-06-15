import Foundation

/// "Aria reads your Gmail" — fetches recent Gmail message metadata (subjects,
/// senders, snippets) through the user's CONNECTED Google account (OAuth/PKCE
/// path, distinct from the EventKit/Apple-Mail `email_recent` tool). Metadata
/// only — never message bodies. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never
/// a crash.
struct GmailRecentTool: AriaTool {
    static let name = "gmail_recent"
    static let description = "Fetch recent Gmail messages (subject, sender, snippet) from the user's connected Google account. Optional input: {query} — a Gmail search like \"from:boss is:unread\". Use for the user's GOOGLE Gmail (not Apple Mail). If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "query": "Optional Gmail search query (e.g. 'from:alice is:unread'); omit for most recent"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Gmail isn't connected yet. Connect Gmail in the app first (Settings → Connectors → Google), then ask me again.")
        }
        let query = input["query"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let messages = try await connector.recentGmail(
                accessToken: token, maxResults: 8,
                query: (query?.isEmpty == false) ? query : nil)
            return .ok(GoogleConnector.formatGmail(messages))
        } catch {
            return .ok("Couldn't reach Gmail right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
