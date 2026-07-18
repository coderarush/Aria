import XCTest
@testable import Aria

private struct AnyTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

final class Part3EvalRecoveryTests: XCTestCase {

    // MARK: - ScenarioLibrary + EvaluationHarness (§61)

    func testScenarioLibraryCoversAllKinds() {
        let kinds = Set(ScenarioLibrary.standard().map(\.kind))
        XCTAssertEqual(kinds, Set(Scenario.Kind.allCases))
    }

    func testHarnessAggregatesCompletion() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(AnyTool(name: "noop"))
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let harness = EvaluationHarness(coordinator: coordinator)

        let scenarios = [
            Scenario(name: "a", kind: .writing, steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"]),
            Scenario(name: "b", kind: .research, steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"]),
            Scenario(name: "c", kind: .coding, steps: [PlanStep(tool: "missing")], rules: ["minCompleted:1"]),
        ]
        let summary = await harness.run(scenarios)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.completed, 2)
        XCTAssertEqual(summary.completionRate, 2.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: - RecoveryEngine (§62)

    func testCheckpointAndRecover() async {
        let recovery = RecoveryEngine(continuity: ContinuityEngine(eventBus: EventBus()))
        let objective = UUID()
        _ = await recovery.checkpoint(objectiveID: objective, state: .executing)
        let recovered = await recovery.recover()
        XCTAssertEqual(recovered?.objectiveID, objective)
    }

    func testRollbackRestoresSpecificCheckpoint() async {
        let recovery = RecoveryEngine(continuity: ContinuityEngine(eventBus: EventBus()))
        let first = await recovery.checkpoint(objectiveID: UUID(), state: .executing)
        _ = await recovery.checkpoint(objectiveID: UUID(), state: .executing)
        let rolled = await recovery.rollback(to: first.id)
        XCTAssertEqual(rolled?.id, first.id)
    }

    func testFailoverUsesFallbackWhenPrimaryFails() async {
        let recovery = RecoveryEngine(continuity: ContinuityEngine(eventBus: EventBus()))
        let usedFallback = await recovery.failover(primary: { false }, fallback: { true })
        XCTAssertTrue(usedFallback)
        let primaryOK = await recovery.failover(primary: { true }, fallback: { false })
        XCTAssertTrue(primaryOK)
    }
}
