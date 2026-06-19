import Foundation

/// Builds a ``ContextEnvelope`` from the Part 1 ``ContextCollector`` plus a
/// rolling history (spec §35). Extends, does not replace, the collector.
///
/// Prediction/recommendation are intentionally simple, deterministic heuristics
/// here; a learned model conforms to the same envelope shape later.
actor ContextAssembler {

    private let collector: ContextCollector
    private var history: [Domain.ContextSnapshot] = []
    private let maxHistory: Int

    init(collector: ContextCollector, maxHistory: Int = 20) {
        self.collector = collector
        self.maxHistory = maxHistory
    }

    func assemble() async -> ContextEnvelope {
        let current = await collector.snapshot()
        let recent = history

        history.append(current)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }

        let predicted = current.activity.map { ["continue:\($0)"] } ?? []
        let recommended = current.apps.map { "review:\($0)" }

        var signals = 0
        if !current.apps.isEmpty { signals += 1 }
        if current.activity != nil { signals += 1 }
        if current.clipboard != nil { signals += 1 }

        return ContextEnvelope(
            current: current,
            recent: recent,
            predicted: predicted,
            recommended: recommended,
            confidence: ContextConfidence(value: Double(signals) / 3.0))
    }
}
