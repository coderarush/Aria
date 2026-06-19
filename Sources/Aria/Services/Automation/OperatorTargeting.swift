import Foundation
import CoreGraphics

/// Operator reliability primitives: how *confident* are we that we located the right
/// control before we click it, and what should the retry loop do when an action fails?
///
/// All decision logic here is PURE and `static`, so it is unit-tested without a live UI
/// (we cannot test real clicks in CI). The thresholds are HEURISTIC — honest defaults,
/// not guarantees. Real-world reliability still needs live-UI iteration.

/// How a target was located, with a normalized 0…1 confidence.
///
/// - Accessibility hits are deterministic: when the AX tree exposes a control whose
///   label matches, we are far more sure than a vision guess, so AX maps to a high
///   confidence band derived from the match score.
/// - Vision matches carry the model's own reported confidence (or a conservative
///   default when the model doesn't report one).
struct TargetingConfidence: Equatable {
    enum Source: Equatable { case accessibility, vision }
    let source: Source
    /// 0.0 (no idea) … 1.0 (certain).
    let value: Double

    init(source: Source, value: Double) {
        self.source = source
        self.value = min(1, max(0, value))
    }

    /// Confidence for an AX hit from its label match score (0…100, see AXReader.matchScore).
    /// An exact label match (100) is near-certain; a weak "contains" match (30) is mediocre.
    /// We never claim 1.0 even on exact, because the right *label* can still be the wrong
    /// element (duplicate buttons) — heuristic, deliberately humble.
    static func fromAX(matchScore: Int) -> TargetingConfidence {
        // 100 → 0.95, 80 → 0.85, 70 → 0.80, 50 → 0.70, 30 → 0.60, 0 → 0.50 (clamped below in init)
        let v = 0.50 + Double(max(0, min(100, matchScore))) / 100.0 * 0.45
        return TargetingConfidence(source: .accessibility, value: v)
    }

    /// Confidence for a vision match. The locator may report its own 0…1 score; if it
    /// doesn't, we assume a cautious mid value (vision is a guess on pixels).
    static func fromVision(score: Double?) -> TargetingConfidence {
        TargetingConfidence(source: .vision, value: score ?? 0.55)
    }
}

/// What to do once we have a candidate target + its confidence.
enum TargetingDecision: Equatable {
    /// Confident enough — perform the action.
    case act
    /// Borderline — don't click a guess; ask the user to confirm first.
    case askFirst
    /// Too unsure (or nothing found) — abort rather than click something random.
    case abort
}

/// A located target: where to click and how sure we are.
struct ResolvedTarget: Equatable {
    /// Screen point to click (CGEvent / top-left coordinate space).
    let point: CGPoint
    let confidence: TargetingConfidence
}

enum OperatorTargeting {
    /// Default confidence floors. Below `askThreshold` we abort; in
    /// [askThreshold, actThreshold) we ask first; at/above `actThreshold` we act.
    static let actThreshold = 0.75
    static let askThreshold = 0.50

    /// PURE decision: given a confidence and an "act" threshold, decide whether to click,
    /// ask first, or abort. Anything at/above `threshold` acts; a band below it asks for
    /// confirmation rather than clicking blindly; far below, abort.
    ///
    /// `askBand` is how far below the act threshold we're still willing to *ask* (vs abort).
    static func decide(confidence: Double,
                       threshold: Double = actThreshold,
                       askBand: Double = 0.25) -> TargetingDecision {
        if confidence >= threshold { return .act }
        if confidence >= threshold - askBand { return .askFirst }
        return .abort
    }

    /// Convenience over a `TargetingConfidence`.
    static func decide(_ c: TargetingConfidence, threshold: Double = actThreshold) -> TargetingDecision {
        decide(confidence: c.value, threshold: threshold)
    }
}

/// What the retry loop should do for a given attempt of a UI action.
///
/// UIs MOVE between attempts (animations settle, lists reflow, sheets appear), so a
/// stale rect from the first attempt is dangerous on retry. The policy says: try once
/// with the target we have; if it fails, RE-RESOLVE the element fresh (re-query AX/vision)
/// and try again; after the budget is spent, give up.
enum RetryAction: Equatable {
    /// First attempt — use the target we already located.
    case attempt
    /// A previous attempt failed — re-locate the element from scratch, then act on the fresh target.
    case reresolveThenRetry
    /// Out of attempts — stop.
    case giveUp
}

enum RetryPolicy {
    /// Default number of total attempts (1 initial + N-1 re-resolved retries).
    static let defaultMaxAttempts = 3

    /// PURE: decide what to do for `attempt` (0-based) given the budget and whether the
    /// previous attempt failed. Attempt 0 always just attempts; later attempts re-resolve
    /// first (never reuse a stale rect); past the budget, give up.
    static func action(attempt: Int,
                       maxAttempts: Int = defaultMaxAttempts,
                       lastFailed: Bool) -> RetryAction {
        if attempt <= 0 { return .attempt }
        if attempt >= maxAttempts { return .giveUp }
        return lastFailed ? .reresolveThenRetry : .attempt
    }
}
