import Foundation

/// A removal candidate surfaced for human review (spec §124).
struct DeleteCandidate: Sendable {
    let symbol: String
    let reason: String
}

/// The delete pass (spec §124) — identifies dead/unreferenced symbols. It only
/// surfaces candidates; it never deletes. The legacy path stays until the
/// migration reaches `.cleanup` (spec §50), so removal is always a deliberate,
/// reviewed step.
struct DeleteAnalyzer: Sendable {

    func analyze(references: [String: Int], entryPoints: Set<String>) -> [DeleteCandidate] {
        references
            .filter { $0.value == 0 && !entryPoints.contains($0.key) }
            .keys
            .sorted()
            .map { DeleteCandidate(symbol: $0, reason: "unreferenced") }
    }
}
