import Foundation

/// One delegated scenario to evaluate (spec §103).
struct ExecutiveScenario: Sendable {
    let objective: String
    let steps: [PlanStep]
    let rules: [String]
    let authority: AutonomyLevel
}

/// Aggregate executive metrics (spec §103).
struct ExecutiveReport: Sendable {
    let total: Int
    let delegatedSuccessfully: Int
    let bar: Double

    var delegationSuccessRate: Double { total == 0 ? 0 : Double(delegatedSuccessfully) / Double(total) }
    var meetsBar: Bool { total > 0 && delegationSuccessRate >= bar }
}

/// Measures whether delegation works (spec §103): runs scenarios through the
/// ``ExecutiveEngine`` and reports the delegation success rate.
actor ExecutiveHarness {

    private let executive: ExecutiveEngine
    private let bar: Double

    init(executive: ExecutiveEngine, bar: Double = 0.8) {
        self.executive = executive
        self.bar = bar
    }

    func run(_ scenarios: [ExecutiveScenario]) async -> ExecutiveReport {
        var succeeded = 0
        for scenario in scenarios {
            let contract = await executive.handle(objective: scenario.objective, steps: scenario.steps,
                                                  rules: scenario.rules, authority: scenario.authority)
            if contract.state == .completed { succeeded += 1 }
        }
        return ExecutiveReport(total: scenarios.count, delegatedSuccessfully: succeeded, bar: bar)
    }
}
