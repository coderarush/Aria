import Foundation

/// Crash/power/network-safe recovery (spec §62) built over the continuity
/// layer: checkpoint, resume, rollback, failover, replay.
actor RecoveryEngine {

    private let continuity: ContinuityEngine

    init(continuity: ContinuityEngine) {
        self.continuity = continuity
    }

    @discardableResult
    func checkpoint(objectiveID: UUID, state: RuntimeState) async -> Checkpoint {
        await continuity.checkpoint(objectiveID: objectiveID, kind: .recovery, state: state)
    }

    /// Resume the most recent checkpoint.
    func recover() async -> Checkpoint? {
        await continuity.resumeLatest()
    }

    /// Roll back to a specific earlier checkpoint.
    func rollback(to id: UUID) async -> Checkpoint? {
        await continuity.restore(id)
    }

    /// Try the primary path; if it reports failure, run the fallback. Returns
    /// whether the work ultimately succeeded.
    func failover(primary: () async -> Bool, fallback: () async -> Bool) async -> Bool {
        if await primary() { return true }
        return await fallback()
    }
}
