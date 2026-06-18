import Foundation

/// How much autonomy an action gets: run silently, surface a suggestion, or
/// pause to ask. This is a READ-ONLY decision unifier — it does not classify or
/// track anything itself, it composes the existing signals:
///   - ActionImportance (Safety.importance)        → reversibility class
///   - ConfirmationPolicy.confirmsDestructive       → user's destructive-confirm pref
///   - BehaviorPattern.successRatio (learning loop) → does this automation work?
///
/// Never returns `.auto` for an important-irreversible action while confirmation
/// is on, and drops a reversible automation that keeps failing to `.suggest`.
enum AutomationLevel: String, Sendable, Equatable {
    case auto      // run silently (still receipted + undoable)
    case suggest   // surface it, wait for the user
    case ask       // pause for explicit approval
}

enum TrustProfile {
    /// `patternSuccessRatio`/`samplesMet` come from the firing pattern's learned
    /// history (PatternEngine); pass nil/false for one-off actions with no history.
    static func advisedLevel(importance: ActionImportance,
                             confirmsDestructive: Bool,
                             patternSuccessRatio: Double? = nil,
                             samplesMet: Bool = false) -> AutomationLevel {
        switch importance {
        case .importantIrreversible:
            // Never auto-fire money/deletes/comms unless the user explicitly
            // opted into zero-friction mode.
            return confirmsDestructive ? .ask : .auto
        case .routine, .reversible:
            // A learned automation that has proven unreliable stops auto-firing.
            if samplesMet, let ratio = patternSuccessRatio, ratio < 0.5 { return .suggest }
            return .auto
        }
    }
}
