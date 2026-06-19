import XCTest
@testable import Aria

private struct NoopTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? { nil }
}

final class IntentPlanningTests: XCTestCase {

    // MARK: - ObjectiveEngine (spec §15)

    func testCreateObjectiveStoresAndEmits() async {
        let bus = EventBus()
        let engine = ObjectiveEngine(eventBus: bus)
        let objective = await engine.createObjective(from: "plan my week")

        XCTAssertEqual(objective.title, "plan my week")
        XCTAssertEqual(objective.status, .created)

        let stored = await engine.objective(objective.id)
        XCTAssertEqual(stored?.id, objective.id)

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.objectiveCreated))
    }

    func testActivateStartsObjective() async {
        let engine = ObjectiveEngine(eventBus: EventBus())
        let objective = await engine.createObjective(from: "x")
        await engine.activate(objective.id)
        let stored = await engine.objective(objective.id)
        XCTAssertEqual(stored?.status, .active)
    }

    func testCancelArchivesObjective() async {
        let engine = ObjectiveEngine(eventBus: EventBus())
        let objective = await engine.createObjective(from: "x")
        await engine.cancel(objective.id)
        let stored = await engine.objective(objective.id)
        XCTAssertEqual(stored?.status, .archived)
    }

    // MARK: - Planner (spec §16)

    func testSequentialPlannerChainsStepsInOrder() throws {
        let objective = Domain.Objective(title: "x", intent: "x")
        let plan = SequentialPlanner().plan(objective: objective, steps: [
            PlanStep(tool: "a"), PlanStep(tool: "b"), PlanStep(tool: "c"),
        ])
        let order = try plan.graph.topologicalOrder()
        let tools = order.map { plan.graph.nodes[$0]!.tool }
        XCTAssertEqual(tools, ["a", "b", "c"])
        XCTAssertEqual(plan.graph.readyNodes(completed: []).count, 1)
    }

    func testPlanCarriesObjectiveID() {
        let objective = Domain.Objective(title: "x", intent: "x")
        let plan = SequentialPlanner().plan(objective: objective, steps: [])
        XCTAssertEqual(plan.objectiveID, objective.id)
    }

    // MARK: - End to end: input → objective → plan → execution

    func testObjectiveToExecutionEndToEnd() async {
        let bus = EventBus()
        let objectives = ObjectiveEngine(eventBus: bus)
        let objective = await objectives.createObjective(from: "do the thing")

        let plan = SequentialPlanner().plan(objective: objective,
                                            steps: [PlanStep(tool: "noop")])

        let engine = ExecutionEngine(eventBus: bus)
        await engine.register(NoopTool(name: "noop"))
        let report = await engine.execute(plan.graph)

        XCTAssertTrue(report.success)
        XCTAssertEqual(report.completed.count, 1)
    }
}
