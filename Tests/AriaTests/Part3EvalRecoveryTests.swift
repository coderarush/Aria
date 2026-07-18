import XCTest
@testable import Aria

private struct AnyTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

private final class SequenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(_ values: [Date]) {
        self.values = values
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

final class Part3EvalRecoveryTests: XCTestCase {

    private func makeCoordinator(clock: SequenceClock) async -> Coordinator {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(AnyTool(name: "noop"))
        return Coordinator(execution: execution, verifier: Verifier(),
                           memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                           eventBus: bus, now: { clock.now() })
    }

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

    func testCoordinatorMeasuresDurationFromInjectedClock() async {
        let start = Date(timeIntervalSince1970: 10)
        let coordinator = await makeCoordinator(clock: SequenceClock([
            start, start.addingTimeInterval(0.125)
        ]))

        let result = await coordinator.run(
            objective: Domain.Objective(title: "measure", intent: "test"),
            steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"])

        XCTAssertEqual(result.duration, 0.125, accuracy: 1e-9)
    }

    func testCoordinatorClampsBackwardClockAdjustment() async {
        let coordinator = await makeCoordinator(clock: SequenceClock([
            Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 9)
        ]))

        let result = await coordinator.run(
            objective: Domain.Objective(title: "clock", intent: "test"),
            steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"])

        XCTAssertEqual(result.duration, 0)
    }

    func testHarnessReportsEachScenarioAndMeasuredAverage() async {
        let zero = Date(timeIntervalSince1970: 0)
        let coordinator = await makeCoordinator(clock: SequenceClock([
            zero, zero.addingTimeInterval(0.010),
            zero.addingTimeInterval(1), zero.addingTimeInterval(1.030)
        ]))
        let harness = EvaluationHarness(coordinator: coordinator)

        let summary = await harness.run([
            Scenario(name: "works", kind: .writing,
                     steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"]),
            Scenario(name: "missing-tool", kind: .coding,
                     steps: [PlanStep(tool: "missing")], rules: ["minCompleted:1"]),
        ])

        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.avgDurationMs, 20, accuracy: 0.001)
        XCTAssertEqual(summary.outcomes.map(\.name), ["works", "missing-tool"])
        XCTAssertEqual(summary.failed.map(\.name), ["missing-tool"])
        XCTAssertEqual(summary.outcomes[0].durationMs, 10, accuracy: 0.001)
        XCTAssertEqual(summary.outcomes[1].durationMs, 30, accuracy: 0.001)
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
