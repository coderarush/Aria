import Foundation

/// "Aria reads a file from your Google Drive" — reads a file from the user's
/// CONNECTED Google Drive by id (or resolves a name via search first) and
/// returns its text. Google-native docs are exported to plain text; binary/other
/// types return a clean "can't read this type" note. Reads its access token
/// solely from `ConnectorStore.validAccessToken`, which auto-refreshes; tokens
/// are never logged. A read, so it doesn't gate. When Google isn't connected it
/// returns a clean setup message, never a crash.
struct DriveReadTool: AriaTool {
    static let name = "drive_read"
    static let description = "Read a file from the user's connected Google Drive. Input: {file_id} (preferred — from drive_search) OR {name} (resolved to the first match by name). Returns the file's text; Google Docs are exported to plain text. If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "file_id": "Drive file id (preferred — get it from drive_search)",
        "name": "File name to look up if you don't have an id (uses the first match)"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let fileID = input["file_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (fileID?.isEmpty == false) || (name?.isEmpty == false) else {
            throw ToolError.missingInput("file_id")
        }
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Google Drive isn't connected yet. Connect Google in the app first (Settings → Connectors → Google), then ask me again.")
        }
        do {
            // Resolve a name to an id when no id was given.
            var id = (fileID?.isEmpty == false) ? fileID! : ""
            if id.isEmpty, let name {
                let matches = try await connector.searchDriveFiles(query: name, accessToken: token)
                guard let first = matches.first else {
                    return .ok("No Google Drive file named \"\(name)\" found.")
                }
                id = first.id
            }
            let result = try await connector.readDriveFile(id: id, accessToken: token)
            return .ok(GoogleConnector.formatDriveRead(result))
        } catch {
            return .ok("Couldn't read that Google Drive file right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
