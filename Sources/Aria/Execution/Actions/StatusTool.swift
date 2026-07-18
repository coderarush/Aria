import Foundation

/// Executive status (Phase 3) — "where do things stand / what next". A thin,
/// deterministic surface over ExecutiveBriefing (output only, no storage).
/// Complements the model-composed daily `briefing` tool; this is the instant
/// goal-centric snapshot.
struct StatusTool: AriaTool {
    static let name = "status"
    static let description = "Executive status — where things stand and what to do next. A deterministic snapshot: current focus, next action, open loops, blocked work, recent progress, and risk alerts. Input: {project?}. Use for ‘what next’, ‘where do things stand’, ‘status’, ‘what should I do’."
    static let paramHints: [String: String] = [
        "project": "limit to one project (optional)"
    ]

    private let briefing: ExecutiveBriefing
    private let now: () -> Date

    init(briefing: ExecutiveBriefing = ExecutiveBriefing(), now: @escaping () -> Date = Date.init) {
        self.briefing = briefing
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let project = input["project"]?.trimmingCharacters(in: .whitespaces)
        let out = await briefing.compose(project: project?.isEmpty == false ? project : nil, now: now())
        return .ok(out.text())
    }
}
