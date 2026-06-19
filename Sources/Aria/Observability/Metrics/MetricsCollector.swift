import Foundation

/// Tallies events by kind (spec §22 metrics). Feed it directly or drain a
/// bus replay into it via ``ingest(_:)``.
actor MetricsCollector {

    private var counts: [AriaEvent.Kind: Int] = [:]

    func record(_ event: AriaEvent) {
        counts[event.kind, default: 0] += 1
    }

    func ingest(_ events: [AriaEvent]) {
        for event in events { record(event) }
    }

    func count(of kind: AriaEvent.Kind) -> Int { counts[kind] ?? 0 }

    func total() -> Int { counts.values.reduce(0, +) }
}
