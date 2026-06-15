import Foundation

/// "Aria finds files in your Google Drive" — searches the user's CONNECTED
/// Google Drive by name and returns matching files (name + id) so a follow-up
/// `drive_read` can open one. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. A read, so it doesn't gate. When Google isn't connected it returns a
/// clean setup message, never a crash.
struct DriveSearchTool: AriaTool {
    static let name = "drive_search"
    static let description = "Search the user's connected Google Drive for files by name. Input: {query} — a search term matched against file names. Returns matching file names and ids (use drive_read with an id to read one). If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "query": "Search term matched against Drive file names (e.g. 'launch plan')"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else { throw ToolError.missingInput("query") }
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Google Drive isn't connected yet. Connect Google in the app first (Settings → Connectors → Google), then ask me again.")
        }
        do {
            let files = try await connector.searchDriveFiles(query: query, accessToken: token)
            return .ok(GoogleConnector.formatDriveFiles(files))
        } catch {
            return .ok("Couldn't reach Google Drive right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
