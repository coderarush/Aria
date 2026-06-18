import Foundation

/// "Continue" — instant, deterministic resume (Phase 2). Powered entirely by the
/// TimelineEngine, which folds GoalEngine + SessionMemory + ContextCoordinator +
/// the work timeline into one answer: the active goal (next action + blockers),
/// or the last saved session, plus the most recent meaningful events. Pure local
/// reads, no model call — the <2s resume path.
struct ContinueTool: AriaTool {
    static let name = "continue"
    static let description = "Resume work instantly — pick up where the user left off. Returns the active goal (its next action and blockers), or the last saved session, plus the most recent meaningful events. Input: {project?}. Use when the user says continue, resume, pick up where I left off, or what was I doing."
    static let paramHints: [String: String] = [
        "project": "limit to one project (optional)"
    ]

    private let engine: TimelineEngine
    private let now: () -> Date

    init(engine: TimelineEngine = .shared, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let project = input["project"]?.trimmingCharacters(in: .whitespaces)
        let at = now()
        let brief = await engine.resumeBrief(project: project?.isEmpty == false ? project : nil, now: at)
        let recent = await engine.recent(3, now: at)
        var out = brief
        if !recent.isEmpty {
            out += "\nRecent:\n" + recent.map { "  • \($0.title)" }.joined(separator: "\n")
        }
        return .ok(out)
    }
}
