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

/// One local, inspectable evaluation result. It contains outcome evidence, not
/// model prompts, user data, access tokens, or telemetry.
struct EvaluationScenarioOutcome: Sendable {
    let name: String
    let kind: Scenario.Kind
    let status: ExecutionContract.Status
    let verificationPassed: Bool
    let durationMs: Double

    var passed: Bool { status == .completed && verificationPassed }
}

/// Aggregate evaluation metrics (spec §61).
struct EvaluationSummary: Sendable {
    let total: Int
    let completed: Int
    let avgDurationMs: Double
    let outcomes: [EvaluationScenarioOutcome]

    var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    var failed: [EvaluationScenarioOutcome] { outcomes.filter { !$0.passed } }

    /// Converts evaluation evidence into a deterministic release decision.  A
    /// high aggregate rate is not enough: each named safety-critical scenario
    /// must have a completed, verified outcome as well.
    func releaseGate(minimumCompletionRate: Double,
                     requiredScenarioNames: [String]) -> EvaluationGate {
        let threshold = min(max(minimumCompletionRate, 0), 1)
        let required = Array(Set(requiredScenarioNames)).sorted()
        let unmetRequired = required.filter { name in
            !outcomes.contains { $0.name == name && $0.passed }
        }
        let ratePassed = completionRate >= threshold
        let passed = ratePassed && unmetRequired.isEmpty

        let rate = Self.percent(completionRate)
        let minimum = Self.percent(threshold)
        let requirementReport = unmetRequired.isEmpty
            ? "all required scenarios passed"
            : "required scenarios failed: \(unmetRequired.joined(separator: ", "))"
        return EvaluationGate(
            passed: passed,
            report: "\(passed ? "PASS" : "FAIL") evaluation gate: completion \(rate) "
                + "(minimum \(minimum)); \(requirementReport)"
        )
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value * 100)
    }
}

/// A local, deterministic decision suitable for release automation. The report
/// is intentionally concise so CI logs expose both the aggregate rate and any
/// failed required scenarios without including user or model data.
struct EvaluationGate: Sendable {
    let passed: Bool
    let report: String
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
        var outcomes: [EvaluationScenarioOutcome] = []
        for scenario in scenarios {
            let objective = Domain.Objective(title: scenario.name, intent: scenario.kind.rawValue)
            let contract = await coordinator.run(objective: objective,
                                                 steps: scenario.steps,
                                                 rules: scenario.rules)
            if contract.status == .completed { completed += 1 }
            outcomes.append(EvaluationScenarioOutcome(
                name: scenario.name,
                kind: scenario.kind,
                status: contract.status,
                verificationPassed: contract.verificationPassed,
                durationMs: max(0, contract.duration * 1_000)))
        }
        let average = outcomes.isEmpty ? 0
            : outcomes.map(\.durationMs).reduce(0, +) / Double(outcomes.count)
        return EvaluationSummary(total: scenarios.count, completed: completed,
                                 avgDurationMs: average, outcomes: outcomes)
    }
}
