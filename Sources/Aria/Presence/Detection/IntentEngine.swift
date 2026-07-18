import Foundation

/// A predicted next action Aria could suggest. Suggest-only — IntentEngine never
/// executes anything; it ranks candidates for the existing surfaces (the proactive
/// presenter / command palette) to offer.
struct PredictedIntent: Sendable, Equatable {
    let action: String
    let confidence: Double
    let reasoning: String
}

/// The world-aware re-ranker. Candidate generation and outcome recording already
/// live in the proactive + learning engines (ProactiveEngine.tick, Suggestion.rank,
/// PatternEngine.recordOutcome) — this does NOT reimplement them. Its one job is
/// the genuinely-new bit: re-rank existing candidates against the live
/// CurrentWorldState so an intent about the app you're in surfaces first.
enum IntentEngine {
    /// Context boost applied when an intent concerns the app currently in focus.
    static let activeAppBoost = 0.15

    /// Filter candidates by a confidence floor, apply a context boost for the
    /// active app, and return them best-first. Pure — no execution, no side effects.
    static func rank(_ candidates: [PredictedIntent],
                     world: CurrentWorldState,
                     floor: Double = 0.55) -> [PredictedIntent] {
        candidates
            .filter { $0.confidence >= floor }
            .map { intent in
                PredictedIntent(action: intent.action,
                                confidence: adjustedConfidence(intent, world: world),
                                reasoning: intent.reasoning)
            }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Shared primitive: boost a base confidence when `text` mentions the app in
    /// focus, capped at 1.0. Used by both this ranker and the proactive engine so
    /// "world-aware" means the same thing everywhere.
    static func boostedConfidence(text: String, base: Double, activeApp: String) -> Double {
        guard !activeApp.isEmpty else { return base }
        return text.lowercased().contains(activeApp.lowercased())
            ? min(1.0, base + activeAppBoost) : base
    }

    private static func adjustedConfidence(_ intent: PredictedIntent, world: CurrentWorldState) -> Double {
        boostedConfidence(text: "\(intent.action) \(intent.reasoning)",
                          base: intent.confidence, activeApp: world.activeApp)
    }
}
