import Foundation

/// "Aria sends a Gmail" — sends an email through the user's CONNECTED Google
/// account (OAuth/PKCE path, distinct from the Apple-Mail `send_mail` tool).
/// EXTERNAL COMMS → `"gmail_send"` is in `Safety.importantTools`, so under high
/// autonomy Aria confirms before sending. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never
/// a crash.
struct GmailSendTool: AriaTool {
    static let name = "gmail_send"
    static let description = "Send an email through the user's connected Google (Gmail) account. Aria confirms before sending. Input: {to, subject?, body}. Use for the user's GOOGLE Gmail (not Apple Mail). If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "to": "Recipient address",
        "subject": "Subject line (optional)",
        "body": "Message body"
    ]
    var isDestructive: Bool { true }   // external comms; also in Safety.importantTools

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let toRaw = input["to"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toRaw.isEmpty else { throw ToolError.missingInput("to") }
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Gmail isn't connected yet. Connect Gmail in the app first (Settings → Connectors → Google), then ask me again.")
        }
        let subject = input["subject"] ?? ""
        let body = input["body"] ?? input["content"] ?? ""
        do {
            let result = try await connector.sendGmail(
                to: toRaw, subject: subject, body: body, accessToken: token)
            await FollowUpTracker.shared.track(subject: subject, recipient: toRaw)
            return .ok("Sent the email to \(toRaw).",
                       diagnostics: "gmail message id \(result.id)")
        } catch {
            return .ok("Couldn't send through Gmail right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
