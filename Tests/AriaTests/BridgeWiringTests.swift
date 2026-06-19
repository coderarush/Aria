import XCTest
@testable import Aria

private struct FakeHandler: CommandHandling {
    let response: AriaResponse
    func handle(command: String, privacyMode: Bool) async -> AriaResponse { response }
}

private struct OKExecTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? { nil }
}

final class BridgeWiringTests: XCTestCase {

    private func noopCoordinator(_ bus: EventBus) -> Coordinator {
        Coordinator(execution: ExecutionEngine(eventBus: bus), verifier: Verifier(),
                    memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)), eventBus: bus)
    }

    func testLegacyAdapterMapsSuccessfulResponse() async {
        let adapter = LegacyOrchestratorAdapter(handler: FakeHandler(
            response: AriaResponse(type: .answer, message: "done", confidence: 0.9)))
        let result = await adapter.execute(BridgeRequest(objective: "do x"))
        XCTAssertEqual(result.output, "done")
        XCTAssertTrue(result.success)
    }

    func testLegacyAdapterPropagatesFailure() async {
        let adapter = LegacyOrchestratorAdapter(handler: FakeHandler(
            response: AriaResponse(type: .action, message: "blocked", succeeded: false)))
        let result = await adapter.execute(BridgeRequest(objective: "y"))
        XCTAssertFalse(result.success)
    }

    func testRuntimeAdapterRunsCoordinator() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(OKExecTool(name: "noop"))
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let adapter = RuntimeCoordinatorAdapter(coordinator: coordinator,
                                                planner: { _ in [PlanStep(tool: "noop")] },
                                                rules: ["minCompleted:1"])
        let result = await adapter.execute(BridgeRequest(objective: "z"))
        XCTAssertTrue(result.success)
    }

    func testBuilderDefaultsToLegacyBehaviorIdentical() async {
        let bus = EventBus()
        let bridge = OrchestratorBridge.make(
            legacyHandler: FakeHandler(response: AriaResponse(type: .answer, message: "legacy-out")),
            runtime: RuntimeCoordinatorAdapter(coordinator: noopCoordinator(bus),
                                               planner: { _ in [] }, rules: []),
            eventBus: bus)
        let stage = await bridge.stage
        XCTAssertEqual(stage, .legacy)
        let outcome = await bridge.execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .legacy)
        XCTAssertEqual(outcome.output, "legacy-out")
    }
}
