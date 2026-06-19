import Foundation

/// The clean close-out of an objective (spec §99).
struct ClosureReport: Sendable {
    let completed: Bool
    let verified: Bool
    let learned: String
    let archived: Bool
    let delegateFurther: Bool
}

/// Closes objectives cleanly (spec §99): completed? verified? learned? archive?
/// delegate further? Records the lesson to memory.
actor ReviewEngine {

    private let memory: MemoryEngine

    init(memory: MemoryEngine) {
        self.memory = memory
    }

    func close(contract: ExecutionContract, learned: String) async -> ClosureReport {
        let completed = contract.status == .completed
        await memory.store(MemoryRecord(
            type: .procedural,
            importance: completed ? 0.7 : 0.5,
            objectiveID: contract.objectiveID,
            summary: "review: \(learned)"))

        return ClosureReport(
            completed: completed,
            verified: contract.verificationPassed,
            learned: learned,
            archived: completed,
            delegateFurther: !completed && contract.recoverable)
    }
}
