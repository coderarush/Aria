import Foundation

/// A single normalized observation (spec §70). Perception produces these — they
/// describe what exists/changed, never an action to take (spec §69).
struct Observation: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let source: String
    var confidence: Double
    var payload: [String: String]
    var embedding: [Double]
    var tags: [String]

    init(id: UUID = UUID(),
         source: String,
         confidence: Double = 1.0,
         payload: [String: String] = [:],
         embedding: [Double] = [],
         tags: [String] = [],
         timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.confidence = confidence
        self.payload = payload
        self.embedding = embedding
        self.tags = tags
    }
}

/// Governs what perception keeps (spec §83): ephemeral-first, bounded retention,
/// consent-based, transparent. Observations are admitted only above a
/// confidence floor; retention is capped.
struct ObservationPolicy: Sendable {
    var minConfidence: Double
    var maxRetained: Int
    var consentRequired: Bool

    init(minConfidence: Double = 0.3, maxRetained: Int = 512, consentRequired: Bool = false) {
        self.minConfidence = minConfidence
        self.maxRetained = maxRetained
        self.consentRequired = consentRequired
    }

    func admits(_ observation: Observation) -> Bool {
        observation.confidence >= minConfidence
    }
}
