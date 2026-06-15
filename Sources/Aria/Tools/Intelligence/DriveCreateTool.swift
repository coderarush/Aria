import Foundation

/// "Aria creates a file in your Google Drive" — creates a plain-text file in the
/// user's CONNECTED Google Drive. Reversible-ish (the file can be trashed from
/// Drive), so it does not gate. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never a
/// crash.
struct DriveCreateTool: AriaTool {
    static let name = "drive_create"
    static let description = "Create a plain-text file in the user's connected Google Drive. Input: {name, content} — name is the file name, content is the text body. Returns the new file's id. If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "name": "File name for the new Drive file (e.g. 'Launch notes.txt')",
        "content": "Plain-text content to write into the file"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { throw ToolError.missingInput("name") }
        // Content may be intentionally empty (create a blank file), but the key
        // must be present so we don't silently create an empty file by accident.
        guard let content = input["content"] else { throw ToolError.missingInput("content") }
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Google Drive isn't connected yet. Connect Google in the app first (Settings → Connectors → Google), then ask me again.")
        }
        do {
            let id = try await connector.createDriveFile(name: name, content: content, accessToken: token)
            return .ok("Created \"\(name)\" in your Google Drive.",
                       diagnostics: "drive file id \(id)")
        } catch {
            return .ok("Couldn't create the Google Drive file right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
