import Foundation

/// The canonical domain model (spec §7) — the objects every subsystem speaks.
///
/// Namespaced under `Domain` so the spec's names (notably `Task`) never collide
/// with the standard library; reference as `Domain.Objective`, `Domain.Task`,
/// etc.
enum Domain {}

extension Domain {

    /// Handling / scheduling priority. Higher cases sort greater.
    enum Priority: Int, Sendable, Comparable {
        case low, normal, high, critical
        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Objective

    /// A desired user outcome.
    struct Objective: Identifiable, Sendable {
        enum Status: String, Sendable {
            case created, active, paused, blocked, completed, failed, archived
        }

        let id: UUID
        var title: String
        var intent: String
        var constraints: [String]
        var priority: Priority
        let createdAt: Date
        var updatedAt: Date
        var confidence: Double
        var successCriteria: [String]
        var status: Status

        init(id: UUID = UUID(),
             title: String,
             intent: String,
             constraints: [String] = [],
             priority: Priority = .normal,
             confidence: Double = 0,
             successCriteria: [String] = [],
             status: Status = .created,
             createdAt: Date = Date()) {
            self.id = id
            self.title = title
            self.intent = intent
            self.constraints = constraints
            self.priority = priority
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.confidence = confidence
            self.successCriteria = successCriteria
            self.status = status
        }

        mutating func start() { status = .active; touch() }
        mutating func pause() { status = .paused; touch() }
        mutating func resume() { status = .active; touch() }
        mutating func complete() { status = .completed; touch() }
        mutating func fail() { status = .failed; touch() }
        mutating func block() { status = .blocked; touch() }
        mutating func archive() { status = .archived; touch() }

        private mutating func touch() { updatedAt = Date() }
    }

    // MARK: - Task

    /// Actionable work that advances an ``Objective``.
    struct Task: Identifiable, Sendable {
        enum Status: String, Sendable { case queued, running, waiting, complete }

        let id: UUID
        var objectiveID: UUID
        var dependencies: [UUID]
        var deadline: Date?
        var estimate: TimeInterval?
        var outputs: [UUID]
        var status: Status

        init(id: UUID = UUID(),
             objectiveID: UUID,
             dependencies: [UUID] = [],
             deadline: Date? = nil,
             estimate: TimeInterval? = nil,
             outputs: [UUID] = [],
             status: Status = .queued) {
            self.id = id
            self.objectiveID = objectiveID
            self.dependencies = dependencies
            self.deadline = deadline
            self.estimate = estimate
            self.outputs = outputs
            self.status = status
        }
    }

    // MARK: - Action

    /// An atomic, tool-backed execution unit.
    struct Action: Identifiable, Sendable {
        enum Permission: String, Sendable { case automatic, requiresApproval, denied }
        enum Status: String, Sendable { case pending, running, succeeded, failed, cancelled }

        let id: UUID
        var tool: String
        var parameters: [String: String]
        var timeout: TimeInterval
        var permission: Permission
        var status: Status

        init(id: UUID = UUID(),
             tool: String,
             parameters: [String: String] = [:],
             timeout: TimeInterval = 30,
             permission: Permission = .automatic,
             status: Status = .pending) {
            self.id = id
            self.tool = tool
            self.parameters = parameters
            self.timeout = timeout
            self.permission = permission
            self.status = status
        }
    }

    // MARK: - Artifact

    /// A concrete output produced by execution (a reference, not the bytes).
    struct Artifact: Identifiable, Sendable {
        enum Kind: String, Sendable {
            case file, email, calendarEvent, message, document, other
        }
        let id: UUID
        var kind: Kind
        var reference: String
        var createdAt: Date

        init(id: UUID = UUID(), kind: Kind, reference: String, createdAt: Date = Date()) {
            self.id = id
            self.kind = kind
            self.reference = reference
            self.createdAt = createdAt
        }
    }

    // MARK: - ContextSnapshot

    /// A capture of current reality at a moment in time.
    struct ContextSnapshot: Sendable {
        var time: Date
        var apps: [String]
        var files: [String]
        var screen: String?
        var clipboard: String?
        var activity: String?
        var objectiveID: UUID?

        init(time: Date = Date(),
             apps: [String] = [],
             files: [String] = [],
             screen: String? = nil,
             clipboard: String? = nil,
             activity: String? = nil,
             objectiveID: UUID? = nil) {
            self.time = time
            self.apps = apps
            self.files = files
            self.screen = screen
            self.clipboard = clipboard
            self.activity = activity
            self.objectiveID = objectiveID
        }
    }

    // MARK: - Memory

    /// Persisted understanding with a scope and optional expiration.
    struct Memory: Identifiable, Sendable {
        enum Scope: String, Sendable { case ephemeral, session, longTerm }

        let id: UUID
        var scope: Scope
        var content: String
        var importance: Double
        var source: String
        var expiration: Date?

        init(id: UUID = UUID(),
             scope: Scope,
             content: String,
             importance: Double = 0.5,
             source: String,
             expiration: Date? = nil) {
            self.id = id
            self.scope = scope
            self.content = content
            self.importance = importance
            self.source = source
            self.expiration = expiration
        }

        func isExpired(asOf now: Date) -> Bool {
            guard let expiration else { return false }
            return expiration < now
        }
    }
}
