import Foundation

/// "Aria adds a note to a Notion page" — appends a paragraph of text to a page in
/// the user's CONNECTED Notion workspace (write, reversible-ish — the block can be
/// deleted, so it does not gate). Reads its access token solely from
/// `ConnectorStore.validAccessToken(.notion)`, which auto-refreshes; tokens are
/// never logged. When Notion isn't connected it returns a clean setup message,
/// never a crash.
struct NotionAppendTool: AriaTool {
    static let name = "notion_append"
    static let description = "Append a paragraph of text to a Notion page by id, in the user's connected Notion workspace. Input: {page_id, text}. If Notion isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "page_id": "The Notion page (or block) id to append to",
        "text": "The text to append as a new paragraph"
    ]

    private let store: ConnectorStore
    private let connector: NotionConnector

    init(store: ConnectorStore = .shared, connector: NotionConnector = NotionConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let pageID = (input["page_id"] ?? input["pageId"] ?? input["page"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !pageID.isEmpty else { throw ToolError.missingInput("page_id") }
        guard let text = (input["text"] ?? input["content"] ?? input["body"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw ToolError.missingInput("text") }
        guard let token = await store.validAccessToken(.notion) else {
            return .ok("Notion isn't connected yet. Connect Notion in the app first (Settings → Connectors → Notion), then ask me again.")
        }
        do {
            let id = try await connector.appendText(pageID: pageID, text: text, accessToken: token)
            return .ok("Added that note to the Notion page.",
                       diagnostics: "notion block id \(id)")
        } catch {
            return .ok("Couldn't update Notion right now. Check the page id, or your connection may need to be re-authorized in the app (Settings → Connectors → Notion).")
        }
    }
}
