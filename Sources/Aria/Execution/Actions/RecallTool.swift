import Foundation

/// "Aria remembers everything" — one recall across ALL of memory at once: past
/// conversations, the user's own indexed files, durable personal context, and
/// work history. Answers "what did I tell Sara about pricing?" without the model
/// having to guess which single store holds the answer. Each hit is tagged with
/// its source ([conversation] / [doc] / [context] / [work]). Local-only.
struct RecallTool: AriaTool {
    static let name = "recall"
    static let description = "Search ALL of Aria's memory at once — past conversations, the user's indexed files, durable personal context, and work history — and return the most relevant hits, each tagged with its source. Input: {query}. Use for open-ended 'what did I/we say/decide/do about X?' questions when you don't know which store holds the answer."
    static let paramHints: [String: String] = [
        "query": "What to recall across conversations, documents, context, and work"
    ]

    private let recall: UnifiedRecall

    init(recall: UnifiedRecall? = nil) {
        // Construct on demand: ConversationMemory has no shared singleton, so load
        // the default on-disk turns read-only; the other stores use their shared
        // instances so we see live state.
        self.recall = recall ?? UnifiedRecall(conversation: ConversationMemory())
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else {
            throw ToolError.missingInput("query")
        }
        let hits = await recall.recall(query, limit: 8)
        guard !hits.isEmpty else {
            return .ok("Nothing across your conversations, files, context, or work matches “\(query)”.")
        }
        let lines = hits.map { h -> String in
            let when = h.timestamp.map { " (\($0.formatted(date: .abbreviated, time: .shortened)))" } ?? ""
            return "\(h.source.tag) \(h.title)\(when)\n  \(h.snippet)"
        }.joined(separator: "\n")
        return .ok("Across your memory:\n\(lines)")
    }
}
