import Foundation

/// Surfaces learned app/command routines as ambient suggestions. Wraps the
/// existing `PatternEngine` (via the injected `fetch`, normally
/// `patternEngine.patternsToSuggest`) so the v8 learning system is preserved,
/// not replaced. Accepting one approves the underlying `BehaviorPattern`.
struct RoutineSignalProvider: SignalProvider {
    let source: SuggestionSource = .routine
    /// How long a freshly surfaced routine suggestion stays live. Default 1h.
    let ttl: TimeInterval
    let fetch: @Sendable (Date) async -> [BehaviorPattern]

    init(ttl: TimeInterval = 3600,
         fetch: @escaping @Sendable (Date) async -> [BehaviorPattern]) {
        self.ttl = ttl
        self.fetch = fetch
    }

    func candidates(now: Date) async -> [Suggestion] {
        let patterns = await fetch(now)
        return patterns.map { Self.suggestion(from: $0, now: now, ttl: ttl) }
    }

    static func suggestion(from p: BehaviorPattern, now: Date, ttl: TimeInterval) -> Suggestion {
        Suggestion(
            source: .routine,
            spokenLine: "\(p.description) — want me to handle that automatically?",
            action: .offerAutomation(patternID: p.id),
            confidence: p.confidence,
            urgency: .ambient,
            createdAt: now,
            expiry: now.addingTimeInterval(ttl),
            dedupeKey: "routine:\(p.id.uuidString)")
    }
}
