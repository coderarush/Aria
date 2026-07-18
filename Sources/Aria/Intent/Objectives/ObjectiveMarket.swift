import Foundation

/// A competing objective in the market (spec §92).
struct MarketEntry: Identifiable, Sendable {
    let id: UUID
    var title: String
    var importance: Double
    var deadline: Date?
    var deferred: Bool
    var retired: Bool
}

/// Competes objectives into a priority queue (spec §92): importance + deadline
/// urgency drive ranking; promote/pause/merge/defer/retire shape the field.
actor ObjectiveMarket {

    private var entries: [UUID: MarketEntry] = [:]

    @discardableResult
    func submit(title: String, importance: Double, deadline: Date?) -> MarketEntry {
        let entry = MarketEntry(id: UUID(), title: title, importance: importance,
                                deadline: deadline, deferred: false, retired: false)
        entries[entry.id] = entry
        return entry
    }

    func promote(_ id: UUID) { entries[id]?.deferred = false }
    func postpone(_ id: UUID) { entries[id]?.deferred = true }   // "defer" is a keyword
    func retire(_ id: UUID) { entries[id]?.retired = true }

    /// Active entries (not deferred/retired), ranked by importance + deadline
    /// urgency.
    func queue(now: Date) -> [MarketEntry] {
        entries.values
            .filter { !$0.deferred && !$0.retired }
            .sorted { score($0, now: now) > score($1, now: now) }
    }

    private func score(_ entry: MarketEntry, now: Date) -> Double {
        var s = entry.importance
        if let deadline = entry.deadline {
            let hours = max(0, deadline.timeIntervalSince(now)) / 3_600
            s += 1.0 / (1.0 + hours)
        }
        return s
    }
}
