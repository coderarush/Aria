import Foundation

/// Converts user input into tracked outcomes (spec §15).
///
/// Pipeline: input → intent → objective. The intent extraction here is the
/// trivial identity (title = intent = input); an LLM-backed interpreter can be
/// injected later without changing the engine's contract. Owns the live set of
/// objectives and emits lifecycle events onto the bus.
actor ObjectiveEngine {

    private var objectives: [UUID: Domain.Objective] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    /// Create an objective from raw user input and register it.
    @discardableResult
    func createObjective(from input: String, priority: Domain.Priority = .normal) async -> Domain.Objective {
        let objective = Domain.Objective(title: input, intent: input, priority: priority)
        objectives[objective.id] = objective
        await eventBus.emit(AriaEvent(
            kind: .objectiveCreated,
            source: "ObjectiveEngine",
            payload: ["id": objective.id.uuidString, "title": input],
            priority: priority == .critical ? .critical : .normal))
        return objective
    }

    func objective(_ id: UUID) -> Domain.Objective? { objectives[id] }

    var all: [Domain.Objective] { Array(objectives.values) }

    /// Move an objective into active execution.
    func activate(_ id: UUID) async {
        guard var objective = objectives[id] else { return }
        objective.start()
        objectives[id] = objective
    }

    /// Mark an objective complete and emit the completion event.
    func complete(_ id: UUID) async {
        guard var objective = objectives[id] else { return }
        objective.complete()
        objectives[id] = objective
        await eventBus.emit(AriaEvent(
            kind: .objectiveCompleted,
            source: "ObjectiveEngine",
            payload: ["id": id.uuidString]))
    }

    /// Cancel an objective by archiving it.
    func cancel(_ id: UUID) async {
        guard var objective = objectives[id] else { return }
        objective.archive()
        objectives[id] = objective
    }
}
