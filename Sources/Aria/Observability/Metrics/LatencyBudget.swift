import Foundation

/// Per-stage latency targets (spec §119, seconds). Every release must show a
/// visible improvement.
struct LatencyBudget: Sendable {

    enum Stage: String, Sendable { case boot, intent, planning, execution, memory, presence }

    private let targets: [Stage: TimeInterval] = [
        .boot: 2.0, .intent: 0.5, .planning: 0.3, .execution: 0.25, .memory: 0.05, .presence: 0.1,
    ]

    func target(_ stage: Stage) -> TimeInterval { targets[stage] ?? .infinity }

    func within(_ stage: Stage, measured: TimeInterval) -> Bool { measured <= target(stage) }

    /// Whether this release improved a stage (current strictly faster).
    func improved(_ stage: Stage, previous: TimeInterval, current: TimeInterval) -> Bool {
        current < previous
    }
}
