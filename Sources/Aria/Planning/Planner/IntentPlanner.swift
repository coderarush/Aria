import Foundation

/// Maps a raw objective into executable steps (spec §16, runtime side). The
/// async signature lets a real implementation call a model; offline planners
/// return synchronously.
protocol IntentPlanner: Sendable {
    func plan(objective: String) async -> [PlanStep]
}

/// A planner that always returns the same steps — for tests and fixed flows.
struct StaticPlanner: IntentPlanner {
    let steps: [PlanStep]
    func plan(objective: String) async -> [PlanStep] { steps }
}

/// A planner backed by a closure (e.g. a deterministic keyword→steps map).
struct ClosureIntentPlanner: IntentPlanner {
    let body: @Sendable (String) async -> [PlanStep]
    func plan(objective: String) async -> [PlanStep] { await body(objective) }
}
