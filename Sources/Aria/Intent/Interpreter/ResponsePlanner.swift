import Foundation

/// Bridges a model's decision to the runtime's input: an ``AriaResponse``'s
/// `actions` (the tool calls the model chose) become ``PlanStep`` values the
/// new execution path can run. Pure and deterministic.
enum ResponsePlanner {
    static func steps(from response: AriaResponse) -> [PlanStep] {
        response.actions.map { PlanStep(tool: $0.tool, parameters: $0.input) }
    }
}

/// An ``IntentPlanner`` that asks a model (any function producing an
/// ``AriaResponse``) for a plan, then maps its actions to steps.
///
/// For live use this needs a *plan-only* model entrypoint — the legacy
/// `AgentOrchestrator.handle` both plans and executes, so plugging it here would
/// double-execute. Until that entrypoint exists, this is wired in shadow/test
/// with a planning function that has no side effects.
struct ModelIntentPlanner: IntentPlanner {
    let planOnly: @Sendable (String) async -> AriaResponse

    init(planOnly: @escaping @Sendable (String) async -> AriaResponse) {
        self.planOnly = planOnly
    }

    func plan(objective: String) async -> [PlanStep] {
        ResponsePlanner.steps(from: await planOnly(objective))
    }
}

extension ModelIntentPlanner {
    /// Build from any plan-only command source (e.g. the real orchestrator).
    init(planner: any CommandPlanning) {
        self.init(planOnly: { await planner.plan(command: $0, privacyMode: false) })
    }
}
