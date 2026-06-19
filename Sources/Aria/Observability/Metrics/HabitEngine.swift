import Foundation

/// How habitual Aria has become (spec §112).
struct HabitScore: Sendable {
    let returnRate: Double
    let delegationRate: Double
    let completionRate: Double

    var composite: Double { (returnRate + delegationRate + completionRate) / 3 }
}

/// Measures default usage (spec §112): return rate, delegation rate, completion
/// rate. Goal: users launch Aria first.
actor HabitEngine {

    private var sessions = 0
    private var returns = 0
    private var objectives = 0
    private var completions = 0
    private var delegations = 0

    func recordSession(returning: Bool) {
        sessions += 1
        if returning { returns += 1 }
    }

    func recordObjective(completed: Bool) {
        objectives += 1
        if completed { completions += 1 }
    }

    func recordDelegation() { delegations += 1 }

    func score() -> HabitScore {
        HabitScore(
            returnRate: sessions == 0 ? 0 : Double(returns) / Double(sessions),
            delegationRate: objectives == 0 ? 0 : Double(delegations) / Double(objectives),
            completionRate: objectives == 0 ? 0 : Double(completions) / Double(objectives))
    }
}
