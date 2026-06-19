import Foundation

/// "Aria searches your Notion" — searches the user's CONNECTED Notion workspace
/// for pages and databases matching a query (read). Reads its access token solely
/// from `ConnectorStore.validAccessToken(.notion)`, which auto-refreshes; tokens
/// are never logged. When Notion isn't connected it returns a clean setup
/// message, never a crash.
struct NotionSearchTool: AriaTool {
    static let name = "notion_search"
    static let description = "Search the user's connected Notion workspace for pages and databases. Input: {query} — what to look for; omit for the most recently edited items. If Notion isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "query": "What to search for in Notion (e.g. 'launch plan'); omit for most recent"
    ]

    private let store: ConnectorStore
    private let connector: NotionConnector

    init(store: ConnectorStore = .shared, connector: NotionConnector = NotionConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = await store.validAccessToken(.notion) else {
            return .ok("Notion isn't connected yet. Connect Notion in the app first (Settings → Connectors → Notion), then ask me again.")
        }
        let query = input["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            let hits = try await connector.search(query: query, accessToken: token)
            return .ok(NotionConnector.formatSearch(hits))
        } catch {
            return .ok("Couldn't reach Notion right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Notion).")
        }
    }
}
