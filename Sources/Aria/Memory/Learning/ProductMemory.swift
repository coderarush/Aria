import Foundation

/// Remembers work patterns (spec §95): preferred workflows, project structures,
/// successful outcomes, repeated actions — as bounded, summarized counts.
/// Never stores raw data, transcripts, or unbounded history.
actor ProductMemory {

    struct WorkPattern: Identifiable, Sendable {
        let id: String
        var kind: String
        var label: String
        var count: Int
    }

    private var patterns: [String: WorkPattern] = [:]
    private let maxPatterns: Int
    private let maxLabelLength = 120

    init(maxPatterns: Int = 256) {
        self.maxPatterns = max(1, maxPatterns)
    }

    func record(kind: String, label rawLabel: String) {
        // Summaries only — never a transcript.
        let label = String(rawLabel.prefix(maxLabelLength))
        let key = kind + "|" + label
        if var existing = patterns[key] {
            existing.count += 1
            patterns[key] = existing
        } else {
            patterns[key] = WorkPattern(id: key, kind: kind, label: label, count: 1)
            evictIfNeeded()
        }
    }

    func top(kind: String?, limit: Int) -> [WorkPattern] {
        patterns.values
            .filter { kind == nil || $0.kind == kind }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    private func evictIfNeeded() {
        guard patterns.count > maxPatterns else { return }
        // Drop the least-frequent pattern (bounded retention).
        if let weakest = patterns.values.min(by: { $0.count < $1.count }) {
            patterns[weakest.id] = nil
        }
    }
}
