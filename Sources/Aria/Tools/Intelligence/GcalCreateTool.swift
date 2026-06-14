import Foundation

/// "Aria adds an event to your Google Calendar" — creates an event on the
/// primary calendar of the user's CONNECTED Google account (OAuth/PKCE path,
/// distinct from the EventKit `calendar` tool). Reversible (the event can be
/// deleted), so it does not gate. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never
/// a crash.
struct GcalCreateTool: AriaTool {
    static let name = "gcal_create"
    static let description = "Create an event on the user's connected Google Calendar (primary). Input: {title, start, end} — start/end are RFC3339 timestamps like \"2026-06-20T15:00:00Z\". Use for the user's GOOGLE Calendar (not the local Apple Calendar). If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "title": "Event title",
        "start": "Start time, RFC3339 (e.g. 2026-06-20T15:00:00Z)",
        "end": "End time, RFC3339 (e.g. 2026-06-20T16:00:00Z)"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let title = input["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { throw ToolError.missingInput("title") }
        guard let start = input["start"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !start.isEmpty else { throw ToolError.missingInput("start") }
        guard let end = input["end"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !end.isEmpty else { throw ToolError.missingInput("end") }
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Google Calendar isn't connected yet. Connect Google in the app first (Settings → Connectors → Google), then ask me again.")
        }
        do {
            let id = try await connector.createEvent(
                title: title, start: start, end: end, accessToken: token)
            return .ok("Added \"\(title)\" to your Google Calendar (\(start)).",
                       diagnostics: "gcal event id \(id)")
        } catch {
            return .ok("Couldn't create the Google Calendar event right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
