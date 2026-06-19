import Foundation

/// Thin GitHub REST API client. Authenticated with a Personal Access Token (no OAuth).
/// The `fetch` closure is injectable for unit tests — production uses URLSession.shared.
struct GitHubService: Sendable {
    static let keychainAccount = "github_personal_access_token"

    var token: String
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(token: String,
         fetch: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse)
             = { try await URLSession.shared.data(for: $0) }) {
        self.token = token
        self.fetch = fetch
    }

    // MARK: - Public API

    /// Returns open issues (not PRs) as formatted text. `repo` must be "owner/repo".
    func issues(repo: String) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/issues?state=open&per_page=10&pulls=false")!
        let data = try await perform(url: url)
        let items = try parseItems(data)
        guard !items.isEmpty else { return "No open issues in \(repo)." }
        let lines = items.map { "#\($0.number) \($0.title) by \($0.user) — \($0.url)" }
        return "Open issues in \(repo):\n\(lines.joined(separator: "\n"))"
    }

    /// Returns open PRs as formatted text. `repo` must be "owner/repo".
    func pullRequests(repo: String) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/pulls?state=open&per_page=10")!
        let data = try await perform(url: url)
        let items = try parseItems(data)
        guard !items.isEmpty else { return "No open pull requests in \(repo)." }
        let lines = items.map { "#\($0.number) \($0.title) by \($0.user) — \($0.url)" }
        return "Open PRs in \(repo):\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Private helpers

    private struct Item {
        let number: Int
        let title: String
        let url: String
        let user: String
    }

    private func perform(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await fetch(req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw GitHubServiceError.httpError(statusCode)
        }
        return data
    }

    private func parseItems(_ data: Data) throws -> [Item] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict -> Item? in
            guard let number = dict["number"] as? Int,
                  let title = dict["title"] as? String,
                  let url = dict["html_url"] as? String else { return nil }
            let userDict = dict["user"] as? [String: Any]
            let user = (userDict?["login"] as? String) ?? "unknown"
            return Item(number: number, title: title, url: url, user: user)
        }
    }
}

enum GitHubServiceError: Error, LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "GitHub API error: HTTP \(code)"
        }
    }
}
