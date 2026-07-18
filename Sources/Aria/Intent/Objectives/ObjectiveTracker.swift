import Foundation

/// Tracks durable objectives and orders them for attention (spec §33).
///
/// Works over the Part 1 ``Domain/Objective`` lifecycle. Surfaces the active
/// set, prioritizes by priority then age (older first, so work doesn't starve),
/// and reports objective age for aging policies.
actor ObjectiveTracker {

    private var objectives: [UUID: Domain.Objective] = [:]

    func track(_ objective: Domain.Objective) { objectives[objective.id] = objective }

    func update(_ objective: Domain.Objective) { objectives[objective.id] = objective }

    func get(_ id: UUID) -> Domain.Objective? { objectives[id] }

    /// Objectives currently active.
    func active() -> [Domain.Objective] {
        objectives.values.filter { $0.status == .active }
    }

    /// Active objectives ordered by priority (high → low), ties broken by age
    /// (older first).
    func prioritized() -> [Domain.Objective] {
        active().sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Seconds since an objective was created, as of `date`.
    func ageInSeconds(of id: UUID, asOf date: Date) -> TimeInterval? {
        guard let objective = objectives[id] else { return nil }
        return date.timeIntervalSince(objective.createdAt)
    }
}
