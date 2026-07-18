import Foundation

/// The outcome of a product-scale run (spec §125).
struct ProductRunResult: Sendable {
    let total: Int
    let completed: Int

    var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    /// Would the user come back? Proxy: a high completion rate.
    var wouldReturn: Bool { completionRate >= 0.8 }
}

/// Runs objectives at product scale (spec §125: 100 / 1k / 10k) and judges
/// whether the user would return.
actor ProductHarness {

    private let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func run(count: Int, steps: [PlanStep], rules: [String]) async -> ProductRunResult {
        var completed = 0
        for i in 0..<count {
            let objective = Domain.Objective(title: "obj-\(i)", intent: "batch")
            let contract = await coordinator.run(objective: objective, steps: steps, rules: rules)
            if contract.status == .completed { completed += 1 }
        }
        return ProductRunResult(total: count, completed: completed)
    }
}
