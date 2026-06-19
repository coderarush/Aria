import Foundation

/// A reusable, parameterized execution recipe (spec §96).
struct ReusableWorkflow: Identifiable, Sendable {
    enum State: String, Sendable { case candidate, approved, active, retired }
    let id: UUID
    var name: String
    var steps: [PlanStep]
    var parameters: [String]
    var state: State
}

/// Discovers reusable execution (spec §96): extract → parameterize → reuse →
/// compose, with a candidate → approved → active → retired lifecycle.
actor WorkflowEngine {

    private var workflows: [UUID: ReusableWorkflow] = [:]

    /// Extract a candidate workflow, parameterizing any `$token` values.
    @discardableResult
    func extract(name: String, steps: [PlanStep]) -> ReusableWorkflow {
        var params: Set<String> = []
        for step in steps {
            for value in step.parameters.values where value.hasPrefix("$") {
                params.insert(String(value.dropFirst()))
            }
        }
        let workflow = ReusableWorkflow(id: UUID(), name: name, steps: steps,
                                        parameters: Array(params), state: .candidate)
        workflows[workflow.id] = workflow
        return workflow
    }

    func get(_ id: UUID) -> ReusableWorkflow? { workflows[id] }

    func approve(_ id: UUID) { workflows[id]?.state = .approved }
    func activate(_ id: UUID) { workflows[id]?.state = .active }
    func retire(_ id: UUID) { workflows[id]?.state = .retired }

    /// Instantiate a workflow's steps, substituting `$token` with provided values.
    func reuse(_ id: UUID, parameters: [String: String]) -> [PlanStep] {
        guard let workflow = workflows[id] else { return [] }
        return workflow.steps.map { step in
            var substituted: [String: String] = [:]
            for (key, value) in step.parameters {
                if value.hasPrefix("$"), let replacement = parameters[String(value.dropFirst())] {
                    substituted[key] = replacement
                } else {
                    substituted[key] = value
                }
            }
            return PlanStep(tool: step.tool, parameters: substituted)
        }
    }

    /// Compose several workflows into one ordered step list.
    func compose(_ ids: [UUID]) -> [PlanStep] {
        ids.compactMap { workflows[$0] }.flatMap(\.steps)
    }
}
