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
        let ref = try RepoRef(repo)
        let url = try Self.url(path: "/repos/\(ref.owner)/\(ref.name)/issues",
                               query: [
                                   URLQueryItem(name: "state", value: "open"),
                                   URLQueryItem(name: "per_page", value: "10")
                               ])
        let data = try await perform(url: url)
        let items = try parseItems(data, includePullRequests: false)
        guard !items.isEmpty else { return "No open issues in \(ref.label)." }
        let lines = items.map { "#\($0.number) \($0.title) by \($0.user) — \($0.url)" }
        return "Open issues in \(ref.label):\n\(lines.joined(separator: "\n"))"
    }

    /// Returns open PRs as formatted text. `repo` must be "owner/repo".
    func pullRequests(repo: String) async throws -> String {
        let ref = try RepoRef(repo)
        let url = try Self.url(path: "/repos/\(ref.owner)/\(ref.name)/pulls",
                               query: [
                                   URLQueryItem(name: "state", value: "open"),
                                   URLQueryItem(name: "per_page", value: "10")
                               ])
        let data = try await perform(url: url)
        let items = try parseItems(data, includePullRequests: true)
        guard !items.isEmpty else { return "No open pull requests in \(ref.label)." }
        let lines = items.map { "#\($0.number) \($0.title) by \($0.user) — \($0.url)" }
        return "Open PRs in \(ref.label):\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Private helpers

    private struct RepoRef {
        let owner: String
        let name: String
        var label: String { "\(owner)/\(name)" }

        init(_ raw: String) throws {
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "/", omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count == 2,
                  Self.valid(parts[0]),
                  Self.valid(parts[1]) else {
                throw GitHubServiceError.invalidRepository(raw)
            }
            owner = parts[0]
            name = parts[1]
        }

        private static func valid(_ part: String) -> Bool {
            !part.isEmpty
            && part.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
            && part != "."
            && part != ".."
        }
    }

    private struct Item {
        let number: Int
        let title: String
        let url: String
        let user: String
    }

    private static func url(path: String, query: [URLQueryItem]) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.github.com"
        comps.path = path
        comps.queryItems = query
        guard let url = comps.url else { throw GitHubServiceError.invalidRepository(path) }
        return url
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

    private func parseItems(_ data: Data, includePullRequests: Bool) throws -> [Item] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict -> Item? in
            if !includePullRequests, dict["pull_request"] != nil { return nil }
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
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "GitHub API error: HTTP \(code)"
        case .invalidRepository(let repo):
            return "Invalid GitHub repository '\(repo)'. Use owner/repo, for example apple/swift."
        }
    }
}
