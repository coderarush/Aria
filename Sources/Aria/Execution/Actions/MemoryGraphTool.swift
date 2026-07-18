import Foundation

/// Connections, not just memory (Phase 12). Surfaces MemoryGraph's relationship
/// queries: why something exists, what's related to it, what led to it, and what
/// changed. Resolves a natural goal reference (title fragment) to a graph node,
/// then reads the relationship layer — which derives everything from the existing
/// stores, so this adds no memory of its own.
struct MemoryGraphTool: AriaTool {
    static let name = "connections"
    static let description = "Explain how the user's work connects — relationships between goals, projects, sessions, and events. Input: {action: why|related|led|changed, subject: a goal title fragment}. why = why we're doing it; related = show related work; led = what led to this; changed = what changed for it. Use for ‘why did we do this’, ‘show related work’, ‘what led to this’, ‘what changed’."
    static let paramHints: [String: String] = [
        "action": "why, related, led, or changed",
        "subject": "a fragment of the goal's title"
    ]

    private let graph: MemoryGraph
    private let goals: GoalEngine
    private let now: () -> Date

    init(graph: MemoryGraph = .shared, goals: GoalEngine = .shared,
         now: @escaping () -> Date = Date.init) {
        self.graph = graph
        self.goals = goals
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let action = (input["action"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard ["why", "related", "led", "changed"].contains(action) else {
            return .fail("Unknown action “\(action)” — use why, related, led, or changed.")
        }
        let ref = (input["subject"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, let goal = await resolve(ref) else {
            return .fail("No goal matches “\(input["subject"] ?? "")”.")
        }
        let node = GraphNode.goal(goal)
        let at = now()

        switch action {
        case "related":
            let nodes = await graph.related(to: node, depth: 2, now: at)
            guard !nodes.isEmpty else { return .ok("Nothing related to ‘\(goal.title)’ yet.") }
            let lines = nodes.map { "  • [\($0.kind.rawValue)] \($0.label)" }.joined(separator: "\n")
            return .ok("Related to ‘\(goal.title)’:\n\(lines)")

        case "why", "led":
            let edges = await graph.trace(from: node, depth: 3, now: at)
            guard !edges.isEmpty else { return .ok("No recorded reasons for ‘\(goal.title)’ yet.") }
            let lines = edges.prefix(8).map {
                "  • \($0.reason) (\($0.source), \(Int($0.confidence * 100))%)"
            }.joined(separator: "\n")
            let head = action == "why" ? "Why ‘\(goal.title)’:" : "What led to ‘\(goal.title)’:"
            return .ok("\(head)\n\(lines)")

        case "changed":
            let events = await graph.neighbors(of: node, now: at)
                .filter { $0.to.kind == .timelineEvent }
            guard !events.isEmpty else { return .ok("Nothing has changed on ‘\(goal.title)’ yet.") }
            let lines = events.prefix(8).map { "  • \($0.to.label)" }.joined(separator: "\n")
            return .ok("Changes on ‘\(goal.title)’:\n\(lines)")

        default:
            return .fail("Unknown action.")
        }
    }

    /// Resolve a title fragment to one goal (exact > unique substring) across all
    /// goals, not just active ones — provenance questions span finished work too.
    private func resolve(_ fragment: String) async -> Goal? {
        let all = await goals.all()
        if let exact = all.first(where: { $0.title.lowercased() == fragment }) { return exact }
        let hits = all.filter { $0.title.lowercased().contains(fragment) }
        return hits.count == 1 ? hits.first : nil
    }
}
