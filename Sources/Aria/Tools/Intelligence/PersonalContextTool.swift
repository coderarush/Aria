import Foundation

/// "Aria knows your world" — searches the Personal Context Engine's ambient
/// signals (recent Downloads/Desktop files, upcoming calendar events) and hands
/// the model grounded context cards. Opt-in and local-only; nothing leaves the
/// machine. Distinct from `knowledge_search`, which reads inside the user's
/// indexed documents — this answers "what's going on around me right now".
struct PersonalContextTool: AriaTool {
    static let name = "personal_context"
    static let description = "Search the user's current personal context — recently downloaded files, files on their Desktop, and upcoming calendar events. Input: {query}. Use when the user refers to something in their world right now (a file they just got, what's coming up, what they're working on)."
    static let paramHints: [String: String] = [
        "query": "What to look for in the user's recent files and upcoming events"
    ]

    private let engine: PersonalContextEngine

    init(engine: PersonalContextEngine = .shared) {
        self.engine = engine
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else {
            throw ToolError.missingInput("query")
        }
        guard await engine.isEnabled else {
            return .ok("Personal context is off. Turn it on in Settings to let me see your recent files and upcoming events.")
        }
        await engine.refresh()
        let cards = await engine.search(query, limit: 8)
        guard !cards.isEmpty else {
            let count = await engine.cardCount
            return .ok(count == 0
                ? "Nothing in your recent files or calendar to draw on yet."
                : "Nothing in your current context matches “\(query)”.")
        }
        let lines = cards.map { card in
            "• [\(card.source.rawValue)] \(card.title):\n  \(card.snippet)"
        }.joined(separator: "\n")
        return .ok("From your world:\n\(lines)")
    }
}
