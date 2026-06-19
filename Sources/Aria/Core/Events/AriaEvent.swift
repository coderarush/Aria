import Foundation

/// An immutable domain event flowing through the ``EventBus``.
///
/// Spec §12 schema: `event` (kind), `timestamp`, `payload`, `source`,
/// `priority`. Events are value types and never mutated after creation.
struct AriaEvent: Sendable, Identifiable {

    /// The canonical event vocabulary. Spec §12 lists the baseline set;
    /// additional runtime-lifecycle kinds are appended as the OS grows.
    enum Kind: String, Sendable, CaseIterable {
        // Perception / context
        case appOpened
        case windowFocused
        case contextChanged
        // Memory
        case memoryStored
        // Execution
        case taskStarted
        case taskCompleted
        case planGenerated
        case toolExecuted
        case verificationPassed
        // Presence
        case presenceOpportunity
        // Runtime lifecycle
        case runtimeStateChanged
        case objectiveCreated
        case objectiveCompleted
        case objectiveFailed
        // Continuity
        case checkpointSaved
        case workResumed
    }

    /// Delivery / handling priority. Higher cases sort greater.
    enum Priority: Int, Sendable, Comparable {
        case low
        case normal
        case high
        case critical

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: UUID
    let kind: Kind
    let timestamp: Date
    let source: String
    let payload: [String: String]
    let priority: Priority

    init(id: UUID = UUID(),
         kind: Kind,
         source: String,
         payload: [String: String] = [:],
         priority: Priority = .normal,
         timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.source = source
        self.payload = payload
        self.priority = priority
        self.timestamp = timestamp
    }
}
