import Foundation

/// Product metadata events (spec §121). No content — events carry no payload.
enum AnalyticsEvent: String, Sendable { case continuation, execution, closure, retention }

/// Aggregate analytics counts (spec §121).
struct AnalyticsSnapshot: Sendable {
    let continuations: Int
    let executions: Int
    let closures: Int
    let retentions: Int
}

/// Tracks product metadata (spec §121): continuation, execution, retention,
/// objective closure. Counts only — never collects content.
actor AnalyticsEngine {

    private var counts: [AnalyticsEvent: Int] = [:]

    func track(_ event: AnalyticsEvent) { counts[event, default: 0] += 1 }

    func snapshot() -> AnalyticsSnapshot {
        AnalyticsSnapshot(continuations: counts[.continuation] ?? 0,
                          executions: counts[.execution] ?? 0,
                          closures: counts[.closure] ?? 0,
                          retentions: counts[.retention] ?? 0)
    }
}
