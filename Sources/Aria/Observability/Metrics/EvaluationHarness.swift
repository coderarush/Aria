import Foundation

/// A reproducible objective to evaluate the runtime against (spec §61).
struct Scenario: Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case research, calendar, writing, coding, browser, multistep, resume, recovery
    }
    let name: String
    let kind: Kind
    let steps: [PlanStep]
    let rules: [String]
}

/// The canonical scenario set — one per kind (spec §61 ScenarioLibrary).
enum ScenarioLibrary {
    static func standard() -> [Scenario] {
        Scenario.Kind.allCases.map { kind in
            Scenario(name: kind.rawValue,
                     kind: kind,
                     steps: [PlanStep(tool: "noop")],
                     rules: ["minCompleted:1"])
        }
    }
}

/// Aggregate evaluation metrics (spec §61).
struct EvaluationSummary: Sendable {
    let total: Int
    let completed: Int
    let avgDurationMs: Double

    var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

/// Runs scenarios through the ``Coordinator`` and measures completion (spec §61).
/// Designed to scale to large batches (the spec's 10k objective runs); here it
/// aggregates whatever scenario set it's given.
actor EvaluationHarness {

    private let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func run(_ scenarios: [Scenario]) async -> EvaluationSummary {
        var completed = 0
        for scenario in scenarios {
            let objective = Domain.Objective(title: scenario.name, intent: scenario.kind.rawValue)
            let contract = await coordinator.run(objective: objective,
                                                 steps: scenario.steps,
                                                 rules: scenario.rules)
            if contract.status == .completed { completed += 1 }
        }
        return EvaluationSummary(total: scenarios.count, completed: completed, avgDurationMs: 0)
    }
}
