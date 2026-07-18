import Foundation

/// "Aria knows your work" — searches the local knowledge index (the user's own
/// PDFs, notes, documents, code) and hands the model grounded snippets with
/// their sources. Local-only retrieval; nothing leaves the machine.
struct KnowledgeSearchTool: AriaTool {
    static let name = "knowledge_search"
    static let description = "Search the user's own indexed files (notes, PDFs, documents, code) for facts, decisions, and content. Input: {query}. Use when the user asks about their own work, projects, files, or past decisions."
    static let paramHints: [String: String] = [
        "query": "What to look for in the user's indexed files"
    ]

    private let index: KnowledgeIndex

    init(index: KnowledgeIndex = .shared) {
        self.index = index
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else {
            throw ToolError.missingInput("query")
        }
        let hits = await index.search(query, limit: 5)
        guard !hits.isEmpty else {
            let count = await index.documentCount
            return .ok(count == 0
                ? "Nothing indexed yet — add folders in Settings → Knowledge, and I'll find nothing until then."
                : "Nothing in your indexed files matches “\(query)”.")
        }
        let lines = hits.map { h in
            "• \(h.title) (\(h.path)):\n  \(h.snippet)"
        }.joined(separator: "\n")
        return .ok("From your files:\n\(lines)")
    }
}
