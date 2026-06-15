import Foundation

/// "Aria knows what it's connected to" — reports which third-party accounts
/// (Google, Notion, Slack) are configured and connected, so the model can tell
/// the user what it can reach and what still needs setup. Read-only; surfaces
/// the clean "not configured" / "not connected" states rather than failing.
struct ConnectorStatusTool: AriaTool {
    static let name = "connector_status"
    static let description = "Report which of the user's external accounts (Google, Notion, Slack) are connected to Aria and which still need setup. No input. Use when the user asks what Aria can access, whether their Gmail/Calendar is connected, or how to connect an account."

    private let store: ConnectorStore

    init(store: ConnectorStore = .shared) {
        self.store = store
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let statuses = await store.connectors()
        let lines = statuses.map { s -> String in
            let state: String
            if s.isConnected {
                let scopeNote = s.scopes.isEmpty ? "" : " (\(s.scopes.count) scope\(s.scopes.count == 1 ? "" : "s"))"
                state = "connected\(scopeNote)"
            } else if s.isConfigured {
                state = "configured, not connected — say \"connect \(s.displayName)\" to authorize"
            } else {
                state = "not configured — add a \(s.displayName) OAuth client ID in Settings to enable"
            }
            return "• \(s.displayName): \(state)"
        }
        return .ok("Account connections:\n\(lines.joined(separator: "\n"))")
    }
}
