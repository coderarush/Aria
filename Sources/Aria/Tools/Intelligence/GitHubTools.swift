import Foundation

/// Lists open GitHub issues for a repository using a Personal Access Token.
/// Returns a not-configured message if no token is stored in the Keychain.
struct GitHubIssuesTool: AriaTool {
    static let name = "github_issues"
    static let description = "List open GitHub issues for a repository. Input: repo (owner/repo format, e.g. 'apple/swift'). Returns not-configured message if no GitHub token set."
    static let paramHints: [String: String] = [
        "repo": "Repository in owner/repo format, e.g. 'apple/swift'"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = KeychainManager.read(account: GitHubService.keychainAccount) else {
            return .ok("GitHub not configured. Add your Personal Access Token in Settings → API Keys.")
        }
        guard let repo = input["repo"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repo.isEmpty else {
            return .ok("Please provide a repo in 'owner/repo' format.")
        }
        do {
            let result = try await GitHubService(token: token).issues(repo: repo)
            return .ok(result)
        } catch {
            return .ok("GitHub error: \(error.localizedDescription)")
        }
    }
}

/// Lists open GitHub pull requests for a repository using a Personal Access Token.
/// Returns a not-configured message if no token is stored in the Keychain.
struct GitHubPRsTool: AriaTool {
    static let name = "github_prs"
    static let description = "List open GitHub pull requests for a repository. Input: repo (owner/repo format). Returns not-configured message if no GitHub token set."
    static let paramHints: [String: String] = [
        "repo": "Repository in owner/repo format, e.g. 'apple/swift'"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = KeychainManager.read(account: GitHubService.keychainAccount) else {
            return .ok("GitHub not configured. Add your Personal Access Token in Settings → API Keys.")
        }
        guard let repo = input["repo"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repo.isEmpty else {
            return .ok("Please provide a repo in 'owner/repo' format.")
        }
        do {
            let result = try await GitHubService(token: token).pullRequests(repo: repo)
            return .ok(result)
        } catch {
            return .ok("GitHub error: \(error.localizedDescription)")
        }
    }
}
