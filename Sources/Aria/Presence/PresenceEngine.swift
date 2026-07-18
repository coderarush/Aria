import Foundation

/// The presence pipeline (spec §37): event → evaluate → opportunity → suggest.
///
/// Presence **notices**; it does not execute (spec §37/§42/§48). `observe`
/// detects opportunities, ranks them, and offers a suggestion for the single
/// best one — nothing runs without explicit downstream approval.
actor PresenceEngine {

    private let detector: OpportunityDetector
    private let ranker: OpportunityRanker
    private let suggestions: SuggestionEngine
    private let eventBus: EventBus

    init(eventBus: EventBus,
         detector: OpportunityDetector,
         ranker: OpportunityRanker,
         suggestions: SuggestionEngine) {
        self.eventBus = eventBus
        self.detector = detector
        self.ranker = ranker
        self.suggestions = suggestions
    }

    /// Observe the current context and, if anything is worth surfacing, offer a
    /// suggestion for the top-ranked opportunity. Returns the suggestions made
    /// (zero or one); never triggers execution.
    func observe(_ context: PresenceContext) async -> [PresenceSuggestion] {
        let opportunities = await detector.detect(context)
        guard let best = ranker.rank(opportunities).first else { return [] }
        let suggestion = await suggestions.suggest(text: best.title, opportunityID: best.id)
        return [suggestion]
    }
}
