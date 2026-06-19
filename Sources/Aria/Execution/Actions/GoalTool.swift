import Foundation

/// Goals as a tool (Phase 1). One verb-dispatched surface for the directive's
/// goal commands: create a goal, advance one (next action / new milestone /
/// mark done), show open blockers, and "continue" the top active goal.
struct GoalTool: AriaTool {
    static let name = "goal"
    static let description = "Track and advance the user's goals — the durable objectives everything attaches to. Input: {action: create|advance|blockers|continue, ...}. create needs title (+ optional project). advance needs goal (a title fragment) plus one of next (set next action), milestone (add a milestone), or done=true (mark complete). blockers lists what's blocking active goals. continue surfaces the top active goal, its next action, and blockers. Use when the user sets a goal, says what they're working toward, asks what's blocking them, or says continue/what next."
    static let paramHints: [String: String] = [
        "action": "create, advance, blockers, or continue",
        "title": "goal title (for create)",
        "project": "project the goal belongs to (optional)",
        "goal": "a fragment of the goal's title to advance (for advance)",
        "next": "the next action to set on the goal (for advance)",
        "milestone": "a milestone to add to the goal (for advance)",
        "done": "true to mark the goal complete (for advance)"
    ]

    private let engine: GoalEngine

    init(engine: GoalEngine = .shared) {
        self.engine = engine
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let action = (input["action"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        switch action {
        case "create":  return await create(input)
        case "advance": return await advance(input)
        case "blockers": return await blockers()
        case "continue": return await resume(input)
        default:
            return .fail("Unknown goal action “\(action)” — use create, advance, blockers, or continue.")
        }
    }

    private func create(_ input: [String: String]) async -> ToolResult {
        let title = input["title"] ?? ""
        guard let goal = await engine.create(title: title, project: input["project"]) else {
            return .fail("A goal needs a title.")
        }
        let proj = goal.project.map { " [\($0)]" } ?? ""
        return .ok("Goal set: \(goal.title)\(proj).")
    }

    private func advance(_ input: [String: String]) async -> ToolResult {
        let ref = input["goal"] ?? ""
        guard let goal = await match(ref) else {
            return .fail(ref.isEmpty
                ? "Which goal? Name part of its title."
                : "No active goal matches “\(ref)”.")
        }
        var changes: [String] = []
        if let next = input["next"], !next.trimmingCharacters(in: .whitespaces).isEmpty {
            _ = await engine.setNextAction(goalID: goal.id, next)
            changes.append("next: \(next)")
        }
        if let m = input["milestone"], !m.trimmingCharacters(in: .whitespaces).isEmpty {
            _ = await engine.addMilestone(goalID: goal.id, title: m)
            changes.append("milestone: \(m)")
        }
        if (input["done"] ?? "").lowercased() == "true" {
            _ = await engine.complete(goalID: goal.id)
            changes.append("marked done")
        }
        guard !changes.isEmpty else {
            return .fail("Nothing to advance — pass next, milestone, or done=true.")
        }
        return .ok("\(goal.title): \(changes.joined(separator: ", ")).")
    }

    private func blockers() async -> ToolResult {
        let open = await engine.blockers()
        guard !open.isEmpty else { return .ok("No blockers on active goals.") }
        let lines = open.map { "• \($0.blocker) — \($0.goalTitle)" }.joined(separator: "\n")
        return .ok("Blockers:\n\(lines)")
    }

    private func resume(_ input: [String: String]) async -> ToolResult {
        guard let digest = await engine.continueDigest(project: input["project"]) else {
            return .ok("No active goal to continue.")
        }
        return .ok("Continue: \(digest)")
    }

    /// Resolve a title fragment to one active goal. Exact (case-insensitive) wins
    /// over substring; an ambiguous fragment with no exact hit returns nil.
    private func match(_ fragment: String) async -> Goal? {
        let q = fragment.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let active = await engine.active()
        if let exact = active.first(where: { $0.title.lowercased() == q }) { return exact }
        let hits = active.filter { $0.title.lowercased().contains(q) }
        return hits.count == 1 ? hits.first : nil
    }
}
