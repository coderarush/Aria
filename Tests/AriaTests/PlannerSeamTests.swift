import XCTest
@testable import Aria

final class PlannerSeamTests: XCTestCase {

    // MARK: - ResponsePlanner (model decision → runtime steps)

    func testResponsePlannerMapsActionsToSteps() {
        let response = AriaResponse(
            type: .multiAction, message: "doing two things",
            actions: [
                AgentAction(tool: "gmail", input: ["to": "a@b"]),
                AgentAction(tool: "calendar", input: ["title": "sync"]),
            ])
        let steps = ResponsePlanner.steps(from: response)
        XCTAssertEqual(steps.map(\.tool), ["gmail", "calendar"])
        XCTAssertEqual(steps.first?.parameters["to"], "a@b")
    }

    func testResponsePlannerEmptyWhenNoActions() {
        let response = AriaResponse(type: .answer, message: "just talking")
        XCTAssertTrue(ResponsePlanner.steps(from: response).isEmpty)
    }

    // MARK: - StaticPlanner / ModelIntentPlanner

    func testStaticPlannerReturnsFixedSteps() async {
        let planner = StaticPlanner(steps: [PlanStep(tool: "noop")])
        let steps = await planner.plan(objective: "anything")
        XCTAssertEqual(steps.map(\.tool), ["noop"])
    }

    func testModelIntentPlannerMapsResponse() async {
        let planner = ModelIntentPlanner { _ in
            AriaResponse(type: .action, message: "x", actions: [AgentAction(tool: "shell", input: ["cmd": "ls"])])
        }
        let steps = await planner.plan(objective: "list files")
        XCTAssertEqual(steps.first?.tool, "shell")
        XCTAssertEqual(steps.first?.parameters["cmd"], "ls")
    }

    // MARK: - RuntimeCoordinatorAdapter uses the planner

    func testAdapterPlansThenExecutes() async {
        let bus = EventBus()
        let execution = ExecutionEngine(eventBus: bus, tools: [AriaToolAdapter(SeamEchoTool())])
        let coordinator = Coordinator(execution: execution, verifier: Verifier(),
                                      memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)),
                                      eventBus: bus)
        let adapter = RuntimeCoordinatorAdapter(
            coordinator: coordinator,
            planner: StaticPlanner(steps: [PlanStep(tool: "echo", parameters: ["msg": "hi"])]),
            rules: ["minCompleted:1"])
        let result = await adapter.execute(BridgeRequest(objective: "say hi"))
        XCTAssertTrue(result.success)
    }
}

private struct SeamEchoTool: AriaTool {
    static let name = "echo"
    static let description = "echo"
    func run(input: [String: String]) async throws -> ToolResult { .ok(input["msg"] ?? "") }
}
