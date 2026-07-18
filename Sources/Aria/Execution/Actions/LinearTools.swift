import Foundation

/// Lists open Linear issues using an API key.
/// Returns a not-configured message if no key is stored in the Keychain.
struct LinearIssuesTool: AriaTool {
    static let name = "linear_issues"
    static let description = "List open Linear issues. Optional input: teamId to filter by team."
    static let paramHints: [String: String] = [
        "teamId": "Optional Linear team ID to filter issues by team"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let apiKey = KeychainManager.read(account: LinearService.keychainAccount) else {
            return .ok("Linear not configured. Add your Linear API key in Settings → API Keys.")
        }
        let teamId = input["teamId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTeamId = (teamId?.isEmpty == false) ? teamId : nil
        do {
            let result = try await LinearService(apiKey: apiKey).issues(teamId: resolvedTeamId)
            return .ok(result)
        } catch {
            return .ok("Linear error: \(error.localizedDescription)")
        }
    }
}

/// Lists Linear projects using an API key.
/// Returns a not-configured message if no key is stored in the Keychain.
struct LinearProjectsTool: AriaTool {
    static let name = "linear_projects"
    static let description = "List Linear projects."

    func run(input: [String: String]) async throws -> ToolResult {
        guard let apiKey = KeychainManager.read(account: LinearService.keychainAccount) else {
            return .ok("Linear not configured. Add your Linear API key in Settings → API Keys.")
        }
        do {
            let result = try await LinearService(apiKey: apiKey).projects()
            return .ok(result)
        } catch {
            return .ok("Linear error: \(error.localizedDescription)")
        }
    }
}
