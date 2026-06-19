import Foundation

/// Where a proactive suggestion came from. Drives per-source settings and the
/// feedback/suppression bookkeeping in `ProactiveStore`.
enum SuggestionSource: String, Codable, Sendable, CaseIterable {
    case calendar
    case routine
    case command
    case screen
    /// V11 P13: a document just landed in Downloads.
    case downloads
    /// V11 P13: a long work session — offer a recap.
    case session
}

/// How urgently a suggestion wants to surface. Time-critical ones (a meeting
/// about to start) outrank ambient ones in ranking and bypass quiet hours.
enum Urgency: Sendable, Equatable {
    case ambient
    case timeCritical
}

/// What happens if the user accepts a suggestion.
enum SuggestionAction: Sendable, Equatable {
    /// Run a natural-language command through the orchestrator.
    case runCommand(String)
    /// Approve a learned `BehaviorPattern` so it becomes an automation.
    case offerAutomation(patternID: UUID)
    /// Informational only — accepting just acknowledges, no side effect.
    case acknowledge
}

/// The outcome of a surfaced suggestion, recorded for the feedback loop.
enum SuggestionOutcome: Sendable, Equatable {
    case accepted
    case dismissed
    case expired
}

/// A single thing Aria might proactively offer. Built by a `SignalProvider`,
/// ranked and de-duplicated by `ProactiveEngine`, surfaced by `SuggestionPresenter`.
struct Suggestion: Identifiable, Sendable, Equatable {
    let id: UUID
    let source: SuggestionSource
    /// The one-line offer Aria speaks when revealed.
    let spokenLine: String
    let action: SuggestionAction
    var confidence: Double
    let urgency: Urgency
    let createdAt: Date
    /// After this instant the suggestion is stale and is dropped silently.
    let expiry: Date
    /// Stable key for a recurring suggestion — used for dedupe + suppression.
    let dedupeKey: String

    init(id: UUID = UUID(),
         source: SuggestionSource,
         spokenLine: String,
         action: SuggestionAction,
         confidence: Double,
         urgency: Urgency,
         createdAt: Date,
         expiry: Date,
         dedupeKey: String) {
        self.id = id
        self.source = source
        self.spokenLine = spokenLine
        self.action = action
        self.confidence = confidence
        self.urgency = urgency
        self.createdAt = createdAt
        self.expiry = expiry
        self.dedupeKey = dedupeKey
    }

    func isExpired(now: Date) -> Bool { now > expiry }

    /// Ordering for picking the single best live suggestion: time-critical first,
    /// then higher confidence, then earlier creation.
    static func rank(_ lhs: Suggestion, before rhs: Suggestion) -> Bool {
        if (lhs.urgency == .timeCritical) != (rhs.urgency == .timeCritical) {
            return lhs.urgency == .timeCritical
        }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        return lhs.createdAt < rhs.createdAt
    }
}
