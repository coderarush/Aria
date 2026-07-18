import Foundation

/// The contract every execution returns (spec §60).
struct ExecutionContract: Sendable {
    enum Status: String, Sendable { case completed, failed }

    let objectiveID: UUID
    let status: Status
    let actions: [UUID]
    let artifacts: [Domain.Artifact]
    let verificationPassed: Bool
    let duration: TimeInterval
    let confidence: Double
    let recoverable: Bool
}

/// Deterministic handoff across the four fixed roles (spec §59): plan →
/// execute → verify → remember. No swarms, no recursion — exactly one of each
/// responsibility, clear ownership.
actor Coordinator {

    private let execution: ExecutionEngine
    private let verifier: Verifier
    private let memory: MemoryEngine
    private let eventBus: EventBus
    private let now: @Sendable () -> Date

    init(execution: ExecutionEngine, verifier: Verifier, memory: MemoryEngine, eventBus: EventBus,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.execution = execution
        self.verifier = verifier
        self.memory = memory
        self.eventBus = eventBus
        self.now = now
    }

    /// Run one objective end to end and return its contract.
    func run(objective: Domain.Objective, steps: [PlanStep], rules: [String]) async -> ExecutionContract {
        let startedAt = now()
        // Plan
        let plan = SequentialPlanner().plan(objective: objective, steps: steps)
        // Execute
        let report = await execution.execute(plan.graph)
        // Verify
        let verification = verifier.verify(report: report, rules: rules)
        let success = report.success && verification.passed
        // Remember
        await memory.store(MemoryRecord(
            type: .procedural,
            importance: success ? 0.8 : 0.4,
            objectiveID: objective.id,
            summary: "ran \(objective.title): \(success ? "ok" : "failed")"))

        let status: ExecutionContract.Status = success ? .completed : .failed
        return ExecutionContract(
            objectiveID: objective.id,
            status: status,
            actions: report.completed,
            artifacts: report.artifacts,
            verificationPassed: verification.passed,
            duration: max(0, now().timeIntervalSince(startedAt)),
            confidence: success ? 1.0 : 0.0,
            recoverable: !success)
    }
}
