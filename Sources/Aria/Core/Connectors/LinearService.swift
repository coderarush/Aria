import Foundation

/// Thin Linear GraphQL API client. Authenticated with an API key (no OAuth).
/// The `fetch` closure is injectable for unit tests — production uses URLSession.shared.
struct LinearService: Sendable {
    static let keychainAccount = "linear_api_key"

    var apiKey: String
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(apiKey: String,
         fetch: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse)
             = { try await URLSession.shared.data(for: $0) }) {
        self.apiKey = apiKey
        self.fetch = fetch
    }

    // MARK: - Public API

    /// Returns open issues as formatted text. Pass `teamId` to filter by team.
    func issues(teamId: String? = nil) async throws -> String {
        let filter: String
        if let teamId {
            filter = "{state: {type: {in: [\\\"started\\\", \\\"unstarted\\\"]}}, team: {id: {eq: \\\"\(teamId)\\\"}}}"
        } else {
            filter = "{state: {type: {in: [\\\"started\\\", \\\"unstarted\\\"]}}}"
        }
        let query = "{ issues(filter: \(filter), first: 10) { nodes { title identifier url assignee { name } } } }"
        let data = try await perform(query: query)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let issuesObj = dataObj["issues"] as? [String: Any],
              let nodes = issuesObj["nodes"] as? [[String: Any]] else {
            return "No open issues found in Linear."
        }
        guard !nodes.isEmpty else { return "No open issues found in Linear." }
        let lines = nodes.compactMap { node -> String? in
            guard let title = node["title"] as? String,
                  let identifier = node["identifier"] as? String,
                  let url = node["url"] as? String else { return nil }
            let assigneeName: String?
            if let assigneeDict = node["assignee"] as? [String: Any],
               let name = assigneeDict["name"] as? String {
                assigneeName = name
            } else {
                assigneeName = nil
            }
            if let assignee = assigneeName {
                return "\(identifier) \(title) — \(assignee) — \(url)"
            } else {
                return "\(identifier) \(title) — \(url)"
            }
        }
        guard !lines.isEmpty else { return "No open issues found in Linear." }
        return "Open Linear issues:\n\(lines.joined(separator: "\n"))"
    }

    /// Returns Linear projects as formatted text.
    func projects() async throws -> String {
        let query = "{ projects(first: 10) { nodes { name description url } } }"
        let data = try await perform(query: query)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let projectsObj = dataObj["projects"] as? [String: Any],
              let nodes = projectsObj["nodes"] as? [[String: Any]] else {
            return "No projects found in Linear."
        }
        guard !nodes.isEmpty else { return "No projects found in Linear." }
        let lines = nodes.compactMap { node -> String? in
            guard let name = node["name"] as? String,
                  let url = node["url"] as? String else { return nil }
            let desc = (node["description"] as? String) ?? ""
            let descDisplay = desc.isEmpty ? "no description" : desc
            return "\(name): \(descDisplay) — \(url)"
        }
        guard !lines.isEmpty else { return "No projects found in Linear." }
        return "Linear projects:\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - Private helpers

    private func perform(query: String) async throws -> Data {
        let url = URL(string: "https://api.linear.app/graphql")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await fetch(req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw LinearServiceError.httpError(statusCode)
        }
        return data
    }
}

enum LinearServiceError: Error, LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Linear API error: HTTP \(code)"
        }
    }
}
