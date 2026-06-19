import Foundation

/// How sure the runtime is about its read of the situation (spec §35).
struct ContextConfidence: Sendable {
    enum Level: String, Sendable { case low, medium, high }

    var value: Double

    var level: Level {
        switch value {
        case ..<0.34: return .low
        case ..<0.67: return .medium
        default: return .high
        }
    }
}

/// The assembled view of context (spec §35): what's happening now, what just
/// happened, what's likely next, and what to do about it — with a confidence.
struct ContextEnvelope: Sendable {
    var current: Domain.ContextSnapshot
    var recent: [Domain.ContextSnapshot]
    var predicted: [String]
    var recommended: [String]
    var confidence: ContextConfidence
}
