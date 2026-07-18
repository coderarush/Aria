import Foundation

/// Makes work resumable (spec §32). Turns "continue" / "finish this" / "what
/// were we doing" into concrete checkpoint capture and restore over a shared
/// ``CheckpointManager``, announcing saves and resumes on the bus.
actor ContinuityEngine {

    private let manager: CheckpointManager
    private let eventBus: EventBus

    init(eventBus: EventBus, manager: CheckpointManager = CheckpointManager()) {
        self.eventBus = eventBus
        self.manager = manager
    }

    /// Capture a checkpoint and announce it.
    @discardableResult
    func checkpoint(objectiveID: UUID?,
                    kind: Checkpoint.Kind = .manual,
                    context: [String: String] = [:],
                    tools: [String] = [],
                    outputs: [UUID] = [],
                    state: RuntimeState = .idle) async -> Checkpoint {
        let checkpoint = Checkpoint(kind: kind, objectiveID: objectiveID,
                                    context: context, tools: tools,
                                    outputs: outputs, state: state.rawValue)
        await manager.capture(checkpoint)
        await eventBus.emit(AriaEvent(
            kind: .checkpointSaved,
            source: "ContinuityEngine",
            payload: ["id": checkpoint.id.uuidString, "kind": kind.rawValue]))
        return checkpoint
    }

    /// Auto-checkpoint when work is paused.
    @discardableResult
    func pause(objectiveID: UUID,
               context: [String: String] = [:],
               state: RuntimeState = .paused) async -> Checkpoint {
        await checkpoint(objectiveID: objectiveID, kind: .automatic,
                         context: context, state: state)
    }

    /// Restore a specific checkpoint.
    func restore(_ id: UUID) async -> Checkpoint? {
        guard let checkpoint = await manager.get(id) else { return nil }
        await announceResume(checkpoint)
        return checkpoint
    }

    /// "continue" — resume the most recent checkpoint.
    func resumeLatest() async -> Checkpoint? {
        guard let checkpoint = await manager.latest() else { return nil }
        await announceResume(checkpoint)
        return checkpoint
    }

    /// Resume the latest checkpoint for a specific objective.
    func resume(objective: UUID) async -> Checkpoint? {
        guard let checkpoint = await manager.latest(forObjective: objective) else { return nil }
        await announceResume(checkpoint)
        return checkpoint
    }

    /// Fork a new line of work from an existing checkpoint.
    func branch(from id: UUID) async -> Checkpoint? {
        guard let source = await manager.get(id) else { return nil }
        let branched = Checkpoint(kind: source.kind, objectiveID: source.objectiveID,
                                  context: source.context, tools: source.tools,
                                  outputs: source.outputs, state: source.state)
        await manager.capture(branched)
        return branched
    }

    private func announceResume(_ checkpoint: Checkpoint) async {
        await eventBus.emit(AriaEvent(
            kind: .workResumed,
            source: "ContinuityEngine",
            payload: ["id": checkpoint.id.uuidString]))
    }
}
