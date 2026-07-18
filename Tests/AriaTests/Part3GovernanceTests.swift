import XCTest
@testable import Aria

private struct OKTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

final class Part3GovernanceTests: XCTestCase {

    // MARK: - ToolGovernor (§53)

    func testHealthUnknownWithoutData() async {
        let governor = ToolGovernor()
        let health = await governor.health("ghost")
        XCTAssertEqual(health, .unknown)
    }

    func testHealthyWhenSuccessRateHigh() async {
        let governor = ToolGovernor()
        for _ in 0..<9 { await governor.record(tool: "gmail", success: true, latency: 0.1) }
        await governor.record(tool: "gmail", success: false, latency: 0.1)
        let health = await governor.health("gmail")
        XCTAssertEqual(health, .healthy)
    }

    func testDisabledWhenSuccessRateLow() async {
        let governor = ToolGovernor()
        for _ in 0..<7 { await governor.record(tool: "flaky", success: false, latency: 0.1) }
        for _ in 0..<3 { await governor.record(tool: "flaky", success: true, latency: 0.1) }
        let health = await governor.health("flaky")
        XCTAssertEqual(health, .disabled)
    }

    func testBlockOverridesHealth() async {
        let governor = ToolGovernor()
        await governor.record(tool: "danger", success: true, latency: 0.1)
        await governor.block("danger")
        let health = await governor.health("danger")
        XCTAssertEqual(health, .blocked)
    }

    // MARK: - CapabilityMatrix (§53)

    func testCapabilityMatrixGatesTools() {
        var matrix = CapabilityMatrix()
        matrix.allow(objectiveKind: "email", tools: ["gmail.send", "gmail.draft"])
        XCTAssertTrue(matrix.isAllowed(tool: "gmail.send", for: "email"))
        XCTAssertFalse(matrix.isAllowed(tool: "slack.send", for: "email"))
        XCTAssertFalse(matrix.isAllowed(tool: "gmail.send", for: "calendar"))
    }

    // MARK: - Coordinator end to end (§59/§60)

    func testCoordinatorRunsObjectiveToContract() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(OKTool(name: "noop"))
        let coordinator = Coordinator(
            execution: execution,
            verifier: Verifier(),
            memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
            eventBus: bus)

        let objective = Domain.Objective(title: "send", intent: "send")
        let contract = await coordinator.run(objective: objective,
                                             steps: [PlanStep(tool: "noop")],
                                             rules: ["minCompleted:1"])
        XCTAssertEqual(contract.status, .completed)
        XCTAssertTrue(contract.verificationPassed)
        XCTAssertEqual(contract.actions.count, 1)
        XCTAssertEqual(contract.objectiveID, objective.id)
    }

    func testCoordinatorFailedObjectiveIsRecoverable() async {
        let bus = EventBus()
        let coordinator = Coordinator(
            execution: ExecutionEngine(eventBus: bus),   // no tool registered → fails
            verifier: Verifier(),
            memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
            eventBus: bus)

        let objective = Domain.Objective(title: "x", intent: "x")
        let contract = await coordinator.run(objective: objective,
                                             steps: [PlanStep(tool: "missing")],
                                             rules: ["minCompleted:1"])
        XCTAssertEqual(contract.status, .failed)
        XCTAssertTrue(contract.recoverable)
    }
}
