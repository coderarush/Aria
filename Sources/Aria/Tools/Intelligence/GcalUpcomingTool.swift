import Foundation

/// "Aria checks your Google Calendar" — lists upcoming events (next ~7 days)
/// from the user's CONNECTED Google account (OAuth/PKCE path, distinct from the
/// EventKit `calendar` tool). Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never
/// a crash.
struct GcalUpcomingTool: AriaTool {
    static let name = "gcal_upcoming"
    static let description = "List upcoming events from the user's connected Google Calendar (next ~7 days). No input. Use for the user's GOOGLE Calendar (not the local Apple Calendar). If Google isn't connected, it says how to connect."

    /// Seven days, in seconds — the forward window the tool requests.
    private static let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Google Calendar isn't connected yet. Connect Google in the app first (Settings → Connectors → Google), then ask me again.")
        }
        do {
            let events = try await connector.upcomingEvents(
                accessToken: token, maxResults: 10, within: Self.sevenDays)
            return .ok(GoogleConnector.formatEvents(events))
        } catch {
            return .ok("Couldn't reach Google Calendar right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
