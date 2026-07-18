import Foundation

struct ResearchTool: AriaTool {
    static let name = "research"
    static let description = "Research a topic by searching the web and synthesizing a structured report. Input: topic (required), depth (optional: 'quick' for 3 sources, 'deep' for 5 sources)."
    static let paramHints: [String: String] = [
        "topic": "The topic to research.",
        "depth": "Research depth: 'quick' (default, 3 sources) or 'deep' (5 sources)."
    ]

    private let gemini: GeminiClient
    private var engine: ResearchEngine

    init(gemini: GeminiClient = GeminiClient(), engine: ResearchEngine = ResearchEngine()) {
        self.gemini = gemini
        self.engine = engine
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let topic = input["topic"], !topic.isEmpty else {
            return .fail("Missing input: topic")
        }
        let depth = input["depth"] ?? "quick"
        let maxSources = depth == "deep" ? 5 : 3

        let outcome = await engine.research(topic: topic, maxSources: maxSources) { [gemini] prompt in
            try await gemini.generateText(prompt: prompt, temperature: 0.3)
        }

        let report = outcome.report
        let summary = "Research complete on '\(topic)': \(report.sections.count) sections, \(report.sources.count) sources used."
        if let savedURL = outcome.savedURL {
            return .ok("\(summary) Saved to \(savedURL.path).")
        }
        return .ok("\(summary) Not saved locally.")
    }
}
