import XCTest
@testable import Aria

private struct FastTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? { nil }
}

final class Part6HarnessGateTests: XCTestCase {

    // MARK: - DeleteAnalyzer (§124) — identify, never delete blind

    func testIdentifiesUnreferencedNonEntrypoints() {
        let analyzer = DeleteAnalyzer()
        let candidates = analyzer.analyze(
            references: ["used": 3, "dead": 0, "main": 0],
            entryPoints: ["main"])
        XCTAssertEqual(candidates.map(\.symbol), ["dead"])
    }

    func testEntrypointsNeverFlagged() {
        let analyzer = DeleteAnalyzer()
        let candidates = analyzer.analyze(references: ["main": 0], entryPoints: ["main"])
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - ProductHarness (§125)

    func testProductHarnessRunsBatchAndJudgesReturn() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(FastTool(name: "noop"))
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let harness = ProductHarness(coordinator: coordinator)
        let result = await harness.run(count: 100, steps: [PlanStep(tool: "noop")], rules: ["minCompleted:1"])
        XCTAssertEqual(result.total, 100)
        XCTAssertEqual(result.completed, 100)
        XCTAssertTrue(result.wouldReturn)
    }

    // MARK: - §126 release gate

    func testPart6ReleaseGate() async {
        let bus = EventBus()

        // Runtime is the live path behind a stage flag.
        let bridge = RuntimeBridge(
            stage: .preferred,
            legacy: GateBridgeLegacy(), runtime: GateBridgeRuntime(), eventBus: bus)
        let outcome = await bridge.execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .runtime)

        // Migration is controllable (promote on parity).
        let controller = MigrationController(stage: .shadow)
        let decision = await controller.decide(parity: ParityReport(
            total: 100, matches: 99, errors: 0, avgOldDuration: 0, avgNewDuration: 0, threshold: 0.95))
        XCTAssertEqual(decision.action, .promote)

        // Daily dogfooding possible.
        let dogfood = DogfoodEngine()
        await dogfood.logFriction(.slow, "x")
        let report = await dogfood.report()
        XCTAssertEqual(report.slow.count, 1)

        // Users choose Aria first (habit measurable).
        let habit = HabitEngine()
        await habit.recordSession(returning: true)
        let score = await habit.score()
        XCTAssertEqual(score.returnRate, 1.0, accuracy: 1e-9)

        // Latency improves release over release.
        XCTAssertTrue(LatencyBudget().improved(.boot, previous: 2.0, current: 1.4))
    }
}

private struct GateBridgeLegacy: LegacyExecutor {
    func execute(_ request: BridgeRequest) async -> BridgeResult { BridgeResult(output: "legacy") }
}
private struct GateBridgeRuntime: RuntimeExecutor {
    func execute(_ request: BridgeRequest) async -> BridgeResult { BridgeResult(output: "runtime") }
}
