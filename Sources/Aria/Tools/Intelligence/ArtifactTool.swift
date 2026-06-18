import Foundation

/// Artifacts as a tool (Phase 5) — surfaces the ArtifactGraph index: the latest
/// thing produced, or artifacts matching a query. Reference index only (returns
/// paths/labels); opening is left to the file/app tools.
struct ArtifactTool: AriaTool {
    static let name = "artifacts"
    static let description = "Find the user's work artifacts — docs, sessions, commits, files. Input: {action: latest|find, kind?: doc|session|commit|file|export, query?}. latest = most recent (optionally of a kind); find = match by name. Use for ‘open latest’, ‘find related work’, ‘continue artifact’."
    static let paramHints: [String: String] = [
        "action": "latest or find",
        "kind": "doc, session, commit, file, or export (optional, for latest)",
        "query": "text to match (for find)"
    ]

    private let graph: ArtifactGraph

    init(graph: ArtifactGraph = .live()) { self.graph = graph }

    func run(input: [String: String]) async throws -> ToolResult {
        switch (input["action"] ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "latest":
            let kind = (input["kind"]).flatMap { Artifact.Kind(rawValue: $0.lowercased()) }
            guard let a = await graph.latest(kind: kind) else { return .ok("No artifacts found.") }
            return .ok("Latest \(a.kind.rawValue): \(a.label) — \(a.id)")
        case "find":
            let hits = await graph.find(input["query"] ?? "")
            guard !hits.isEmpty else { return .ok("No artifacts match.") }
            return .ok("Artifacts:\n" + hits.prefix(8).map { "  • [\($0.kind.rawValue)] \($0.label)" }.joined(separator: "\n"))
        default:
            return .fail("Unknown action — use latest or find.")
        }
    }
}
