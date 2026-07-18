import Foundation

/// An ordered, replayable record of runtime events (spec §22 timeline).
actor ExecutionTimeline {

    struct Entry: Sendable {
        let timestamp: Date
        let kind: AriaEvent.Kind
        let source: String
    }

    private(set) var entries: [Entry] = []

    func record(_ event: AriaEvent) {
        entries.append(Entry(timestamp: event.timestamp, kind: event.kind, source: event.source))
    }

    func ingest(_ events: [AriaEvent]) {
        for event in events { record(event) }
    }

    /// The most recent `n` entries, oldest first.
    func recent(_ n: Int) -> [Entry] {
        Array(entries.suffix(n))
    }
}
