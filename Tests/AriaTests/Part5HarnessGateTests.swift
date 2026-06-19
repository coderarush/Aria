import XCTest
@testable import Aria

private struct ShipTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

final class Part5HarnessGateTests: XCTestCase {

    private func executive(bus: EventBus, registerTool: Bool) async -> ExecutiveEngine {
        let execution = ExecutionEngine(eventBus: bus)
        if registerTool { await execution.register(ShipTool(name: "noop")) }
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        return ExecutiveEngine(delegation: DelegationEngine(eventBus: bus), coordinator: coordinator)
    }

    // MARK: - ExecutiveHarness (§103)

    func testHarnessMeasuresDelegationSuccess() async {
        let bus = EventBus()
        let harness = ExecutiveHarness(executive: await executive(bus: bus, registerTool: true), bar: 0.5)
        let scenarios = [
            ExecutiveScenario(objective: "a", steps: [PlanStep(tool: "noop")],
                              rules: ["minCompleted:1"], authority: .execute),
            ExecutiveScenario(objective: "b", steps: [PlanStep(tool: "missing")],
                              rules: ["minCompleted:1"], authority: .execute),
        ]
        let report = await harness.run(scenarios)
        XCTAssertEqual(report.total, 2)
        XCTAssertEqual(report.delegatedSuccessfully, 1)
        XCTAssertEqual(report.delegationSuccessRate, 0.5, accuracy: 1e-9)
    }

    // MARK: - §105 release gate

    func testPart5ReleaseGate() async {
        let bus = EventBus()

        // Delegates naturally + executes under authority.
        let executive = await executive(bus: bus, registerTool: true)
        let contract = await executive.handle(objective: "ship", steps: [PlanStep(tool: "noop")],
                                              rules: ["minCompleted:1"], authority: .execute)
        XCTAssertEqual(contract.state, .completed)

        // Objectives close cleanly.
        let memory = MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0))
        let closure = await ReviewEngine(memory: memory).close(
            contract: ExecutionContract(objectiveID: UUID(), status: .completed, actions: [UUID()],
                                        artifacts: [], verificationPassed: true, duration: 0,
                                        confidence: 1, recoverable: false),
            learned: "ok")
        XCTAssertTrue(closure.archived)

        // Continuity maintained.
        let continuity = ContinuityEngine(eventBus: bus)
        let checkpoint = await continuity.checkpoint(objectiveID: UUID(), tools: ["x"], state: .executing)
        let resumed = await continuity.resumeLatest()
        XCTAssertEqual(resumed?.id, checkpoint.id)

        // Execution remains trusted.
        let trust = TrustEngine()
        await trust.recordVerification(passed: true)
        let confidence = await trust.confidence()
        XCTAssertGreaterThan(confidence, 0)

        // Glass feels useful without hardware.
        let glass = GlassRuntime()
        await GlassExperience(glass: glass).display(
            StreamState(objective: "ship", status: "done", attention: "calm", context: "shipped", memory: []))
        let hud = await glass.hud
        XCTAssertEqual(hud.objective, "ship")
    }
}
