import Foundation

/// A durable container of related work (spec §34): objectives, artifacts,
/// memories, an optional deadline, and a continuity status.
struct Project: Identifiable, Sendable {
    enum Status: String, Sendable { case open, closed }

    let id: UUID
    var name: String
    var objectiveIDs: [UUID]
    var artifactIDs: [UUID]
    var memoryIDs: [UUID]
    var deadline: Date?
    var status: Status

    init(id: UUID = UUID(), name: String, deadline: Date? = nil) {
        self.id = id
        self.name = name
        self.objectiveIDs = []
        self.artifactIDs = []
        self.memoryIDs = []
        self.deadline = deadline
        self.status = .open
    }
}

/// Manages projects (spec §34): create, accumulate work, summarize, close.
actor ProjectEngine {

    private var projects: [UUID: Project] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    @discardableResult
    func create(name: String, deadline: Date?) async -> Project {
        let project = Project(name: name, deadline: deadline)
        projects[project.id] = project
        return project
    }

    func get(_ id: UUID) -> Project? { projects[id] }

    func addObjective(_ objectiveID: UUID, to projectID: UUID) {
        projects[projectID]?.objectiveIDs.append(objectiveID)
    }

    func addArtifact(_ artifactID: UUID, to projectID: UUID) {
        projects[projectID]?.artifactIDs.append(artifactID)
    }

    func addMemory(_ memoryID: UUID, to projectID: UUID) {
        projects[projectID]?.memoryIDs.append(memoryID)
    }

    /// A one-line summary of a project's contents.
    func summarize(_ id: UUID) -> String {
        guard let project = projects[id] else { return "" }
        return "\(project.name): \(project.objectiveIDs.count) objectives, "
            + "\(project.artifactIDs.count) artifacts, \(project.memoryIDs.count) memories"
    }

    func close(_ id: UUID) {
        projects[id]?.status = .closed
    }

    /// All open projects.
    func open() -> [Project] {
        projects.values.filter { $0.status == .open }
    }
}
