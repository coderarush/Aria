import Foundation

/// "Aria drafts a Gmail" — creates a DRAFT (does NOT send) in the user's
/// CONNECTED Google account. Reversible prep, so it does not gate. Distinct from
/// the Apple-Mail `email_draft` tool. Reads its access token solely from
/// `ConnectorStore.validAccessToken`, which auto-refreshes; tokens are never
/// logged. When Google isn't connected it returns a clean setup message, never
/// a crash.
struct GmailDraftTool: AriaTool {
    static let name = "gmail_draft"
    static let description = "Create a Gmail DRAFT (does not send) in the user's connected Google account. Input: {to?, subject?, body}. Use to prepare a Gmail message for the user to review and send. If Google isn't connected, it says how to connect."
    static let paramHints: [String: String] = [
        "to": "Recipient address (optional)",
        "subject": "Subject line (optional)",
        "body": "Message body"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector

    init(store: ConnectorStore = .shared, connector: GoogleConnector = GoogleConnector()) {
        self.store = store
        self.connector = connector
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Gmail isn't connected yet. Connect Gmail in the app first (Settings → Connectors → Google), then ask me again.")
        }
        let to = input["to"] ?? ""
        let subject = input["subject"] ?? ""
        let body = input["body"] ?? input["content"] ?? ""
        do {
            let result = try await connector.createDraft(
                to: to, subject: subject, body: body, accessToken: token)
            // Make this receipt undoable: the chokepoint snapshots UndoStack depth
            // around the call and attaches this action so "undo" deletes the draft.
            await UndoStack.shared.record(.gmailDraftCreated(id: result.id))
            let suffix = to.isEmpty ? "" : " to \(to)"
            return .ok("Drafted the email in Gmail\(suffix) — review and send when you're ready.",
                       diagnostics: "gmail draft id \(result.id)")
        } catch {
            return .ok("Couldn't create the Gmail draft right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }
    }
}
