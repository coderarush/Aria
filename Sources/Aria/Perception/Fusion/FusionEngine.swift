import Foundation

/// The fused, cross-modal picture of the moment (spec §75).
struct UnifiedContext: Sendable {
    let current: String
    let recent: [String]
    let confidence: Double
    let ambiguity: Double
    let recommendations: [String]
}

/// Reconciles observations before fusion (spec §75): drops stale ones and
/// collapses duplicates (same source+payload), keeping the newest.
struct ConflictResolver: Sendable {

    func resolve(_ observations: [Observation], now: Date, staleAfter: TimeInterval) -> [Observation] {
        let fresh = observations.filter { now.timeIntervalSince($0.timestamp) <= staleAfter }

        var newestByKey: [String: Observation] = [:]
        for observation in fresh {
            let key = observation.source + "|" + observation.payload.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            if let existing = newestByKey[key], existing.timestamp >= observation.timestamp { continue }
            newestByKey[key] = observation
        }
        return Array(newestByKey.values)
    }
}

/// Fuses observations into a ``UnifiedContext`` (spec §75). The highest-
/// confidence observation drives `current`; ambiguity reflects how many
/// distinct sources disagree.
actor FusionEngine {

    private let resolver: ConflictResolver

    init(resolver: ConflictResolver = ConflictResolver()) {
        self.resolver = resolver
    }

    func fuse(_ observations: [Observation], now: Date, staleAfter: TimeInterval = 3_600) -> UnifiedContext {
        let resolved = resolver.resolve(observations, now: now, staleAfter: staleAfter)
        guard !resolved.isEmpty else {
            return UnifiedContext(current: "", recent: [], confidence: 0, ambiguity: 0, recommendations: [])
        }

        let ranked = resolved.sorted { $0.confidence > $1.confidence }
        let current = ranked.first.map { $0.payload["summary"] ?? $0.source } ?? ""
        let recent = ranked.map { $0.payload["summary"] ?? $0.source }
        let confidence = resolved.map(\.confidence).reduce(0, +) / Double(resolved.count)
        let distinctSources = Set(resolved.map(\.source)).count
        let ambiguity = distinctSources <= 1 ? 0 : Double(distinctSources - 1) / Double(distinctSources)

        return UnifiedContext(current: current, recent: recent, confidence: confidence,
                              ambiguity: ambiguity, recommendations: [])
    }
}
