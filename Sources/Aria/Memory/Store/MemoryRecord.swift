import Foundation

/// The richer Memory-OS record (spec §29) layered over the Part 1
/// ``Domain/Memory``. Carries the signals retrieval and lifecycle need:
/// type, importance, confidence, the owning objective, captured context, an
/// embedding slot, a summary, produced artifacts, and an optional expiry.
struct MemoryRecord: Identifiable, Sendable {

    /// The six memory classes (spec §28).
    enum MemoryType: String, Sendable {
        case working, session, project, preference, episodic, procedural
    }

    let id: UUID
    let timestamp: Date
    var scope: Domain.Memory.Scope
    var type: MemoryType
    var importance: Double
    var confidence: Double
    var objectiveID: UUID?
    var context: [String: String]
    var embedding: [Double]
    var summary: String
    var artifacts: [UUID]
    var expiration: Date?

    init(id: UUID = UUID(),
         type: MemoryType,
         scope: Domain.Memory.Scope = .session,
         importance: Double = 0.5,
         confidence: Double = 0.5,
         objectiveID: UUID? = nil,
         context: [String: String] = [:],
         embedding: [Double] = [],
         summary: String = "",
         artifacts: [UUID] = [],
         timestamp: Date = Date(),
         expiration: Date? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.scope = scope
        self.type = type
        self.importance = importance
        self.confidence = confidence
        self.objectiveID = objectiveID
        self.context = context
        self.embedding = embedding
        self.summary = summary
        self.artifacts = artifacts
        self.expiration = expiration
    }

    func isExpired(asOf now: Date) -> Bool {
        guard let expiration else { return false }
        return expiration < now
    }
}
