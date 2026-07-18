import Foundation

/// Rewind / step / diff / export over a recorded event log (spec §56).
struct ReplayEngine: Sendable {

    private let events: [AriaEvent]

    init(_ events: [AriaEvent]) { self.events = events }

    /// Events in chronological order.
    func timeline() -> [AriaEvent] {
        events.sorted { $0.timestamp < $1.timestamp }
    }

    /// State as of `index`: every event up to and including it.
    func step(to index: Int) -> [AriaEvent] {
        guard index >= 0 else { return [] }
        return Array(events.prefix(index + 1))
    }

    /// Rewind to an earlier point — alias for ``step(to:)``.
    func rewind(to index: Int) -> [AriaEvent] { step(to: index) }

    /// Events strictly after `from` and up to `to`.
    func diff(from: Int, to: Int) -> [AriaEvent] {
        let lower = max(0, from + 1)
        let upper = min(events.count - 1, to)
        guard lower <= upper else { return [] }
        return Array(events[lower...upper])
    }

    /// A flat, exportable rendering of the log.
    func export() -> String {
        timeline().map { "\($0.timestamp.timeIntervalSince1970):\($0.kind.rawValue)@\($0.source)" }
            .joined(separator: "\n")
    }
}
