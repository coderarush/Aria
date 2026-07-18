import XCTest
@testable import Aria

private struct DoneTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

final class Part5ExecutiveTests: XCTestCase {

    // MARK: - DelegationEngine (§90)

    func testDelegateCreatesRequestedContract() async {
        let engine = DelegationEngine(eventBus: EventBus())
        let contract = await engine.delegate(objective: "book flight", constraints: ["under $400"],
                                             authority: .suggest, deadline: nil,
                                             verification: ["minCompleted:1"], success: "ticket booked")
        XCTAssertEqual(contract.state, .requested)
        XCTAssertEqual(contract.objective, "book flight")
        XCTAssertEqual(contract.constraints, ["under $400"])
    }

    func testAcceptAndReport() async {
        let engine = DelegationEngine(eventBus: EventBus())
        let contract = await engine.delegate(objective: "x", constraints: [], authority: .execute,
                                             deadline: nil, verification: [], success: "")
        await engine.setState(contract.id, .accepted)
        let stored = await engine.get(contract.id)
        XCTAssertEqual(stored?.state, .accepted)
        let report = await engine.report(contract.id)
        XCTAssertTrue(report.contains("accepted"))
    }

    // MARK: - ExecutiveEngine (§89) — earns authority, never assumes

    func testHandleWithAuthorityExecutesToCompletion() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus)
        await execution.register(DoneTool(name: "noop"))
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let executive = ExecutiveEngine(delegation: DelegationEngine(eventBus: bus),
                                        coordinator: coordinator)

        let contract = await executive.handle(objective: "ship", steps: [PlanStep(tool: "noop")],
                                              rules: ["minCompleted:1"], authority: .execute)
        XCTAssertEqual(contract.state, .completed)
    }

    func testHandleWithoutAuthorityPreparesWithoutExecuting() async {
        let bus = EventBus()
        let coordinator = Coordinator(execution: ExecutionEngine(eventBus: bus), verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let executive = ExecutiveEngine(delegation: DelegationEngine(eventBus: bus),
                                        coordinator: coordinator)

        let contract = await executive.handle(objective: "send email", steps: [PlanStep(tool: "noop")],
                                              rules: ["minCompleted:1"], authority: .suggest)
        // Suggest authority cannot execute — prepared and awaiting approval.
        XCTAssertEqual(contract.state, .review)
        // Nothing executed → no taskStarted emitted.
        let kinds = await bus.replay().map(\.kind)
        XCTAssertFalse(kinds.contains(.taskStarted))
    }
}
