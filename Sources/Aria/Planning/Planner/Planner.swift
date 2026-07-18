import Foundation

/// A single intended step in a plan, before it becomes a concrete
/// ``Domain/Action`` inside the graph.
struct PlanStep: Sendable {
    let tool: String
    let parameters: [String: String]

    init(tool: String, parameters: [String: String] = [:]) {
        self.tool = tool
        self.parameters = parameters
    }
}

/// The output of planning (spec §16): the executable graph plus the contract
/// the result will be checked against.
struct ExecutionPlan: Sendable {
    let objectiveID: UUID
    let graph: ExecutionGraph
    let expectedArtifacts: [Domain.Artifact.Kind]
    let verificationRules: [String]
}

/// Turns an objective into an ``ExecutionPlan`` (spec §16): decomposition,
/// ordering, parallelization, verification.
protocol Planner: Sendable {
    func plan(objective: Domain.Objective, steps: [PlanStep]) -> ExecutionPlan
}

/// A planner that lays steps out as a strict sequence — each action depends on
/// the previous one. The simplest correct decomposition; richer planners
/// (parallel branches, LLM decomposition) conform to the same protocol.
struct SequentialPlanner: Planner {

    func plan(objective: Domain.Objective, steps: [PlanStep]) -> ExecutionPlan {
        var graph = ExecutionGraph()
        var previous: UUID?
        for step in steps {
            let action = Domain.Action(tool: step.tool, parameters: step.parameters)
            graph.addAction(action, dependsOn: previous.map { [$0] } ?? [])
            previous = action.id
        }
        return ExecutionPlan(
            objectiveID: objective.id,
            graph: graph,
            expectedArtifacts: [],
            verificationRules: objective.successCriteria)
    }
}
