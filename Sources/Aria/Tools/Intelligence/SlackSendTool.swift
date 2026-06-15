import Foundation

/// "Aria posts to Slack" — sends a message to a channel in the user's CONNECTED
/// Slack workspace. EXTERNAL COMMS → `"slack_send"` is in `Safety.importantTools`,
/// so under high autonomy Aria confirms before posting. Reads its access token
/// solely from `ConnectorStore.validAccessToken(.slack)`, which auto-refreshes;
/// tokens are never logged. When Slack isn't connected it returns a clean setup
/// message, never a crash.
struct SlackSendTool: AriaTool {
    static let name = "slack_send"
    static let description = "Post a message to a Slack channel in the user's connected Slack workspace. Aria confirms before posting. Input: {channel, text} — channel is an id like \"C0123ABCD\". If Slack isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "channel": "The Slack channel id to post to (e.g. C0123ABCD)",
        "text": "The message text to post"
    ]
    var isDestructive: Bool { true }   // external comms; also in Safety.importantTools

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
        guard let text = (input["text"] ?? input["message"] ?? input["body"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw ToolError.missingInput("text") }
        guard let token = await store.validAccessToken(.slack) else {
            return .ok("Slack isn't connected yet. Connect Slack in the app first (Settings → Connectors → Slack), then ask me again.")
        }
        do {
            let result = try await connector.sendMessage(channel: channel, text: text, accessToken: token)
            return .ok("Posted your message to Slack.",
                       diagnostics: "slack channel \(result.channel) ts \(result.ts)")
        } catch {
            return .ok("Couldn't post to Slack right now. Check the channel id, or your connection may need to be re-authorized in the app (Settings → Connectors → Slack).")
        }
    }
}
