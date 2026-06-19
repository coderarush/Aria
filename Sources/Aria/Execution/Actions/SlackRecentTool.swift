import Foundation

/// "Aria reads a Slack channel" — fetches recent messages from a channel in the
/// user's CONNECTED Slack workspace (read). Reads its access token solely from
/// `ConnectorStore.validAccessToken(.slack)`, which auto-refreshes; tokens are
/// never logged. When Slack isn't connected it returns a clean setup message,
/// never a crash.
struct SlackRecentTool: AriaTool {
    static let name = "slack_recent"
    static let description = "Fetch recent messages from a Slack channel in the user's connected Slack workspace. Input: {channel} — a channel id like \"C0123ABCD\". If Slack isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "channel": "The Slack channel id to read (e.g. C0123ABCD)"
    ]

    private let store: ConnectorStore
    private let connector: SlackConnector

    init(store: ConnectorStore = .shared, connector: SlackConnector = SlackConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let channel = (input["channel"] ?? input["channel_id"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !channel.isEmpty else { throw ToolError.missingInput("channel") }
        guard let token = await store.validAccessToken(.slack) else {
            return .ok("Slack isn't connected yet. Connect Slack in the app first (Settings → Connectors → Slack), then ask me again.")
        }
        do {
            let messages = try await connector.recentMessages(channel: channel, accessToken: token)
            return .ok(SlackConnector.formatMessages(messages))
        } catch {
            return .ok("Couldn't read that Slack channel right now. Check the channel id, or your connection may need to be re-authorized in the app (Settings → Connectors → Slack).")
        }
    }
}
