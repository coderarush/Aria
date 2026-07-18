import XCTest
@testable import Aria

private struct NoopExecTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: name)
    }
}

/// End-to-end: boot the runtime, then drive a user intent all the way to a
/// verified outcome with observability — the spec's perception→…→improvement
/// spine in one test.
final class RuntimeIntegrationTests: XCTestCase {

    func testBootProducesIdleRuntime() async {
        let container = await AppBootstrapper().boot()
        let state = await container.runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testFullPipelineBootToVerifiedOutcome() async {
        let container = await AppBootstrapper().boot()
        await container.execution.register(NoopExecTool(name: "noop"))

        // Intent → objective
        let objective = await container.objectives.createObjective(from: "ship it")
        await container.objectives.activate(objective.id)

        // Plan → execute
        let plan = SequentialPlanner().plan(objective: objective,
                                            steps: [PlanStep(tool: "noop"), PlanStep(tool: "noop")])
        let report = await container.execution.execute(plan.graph)
        XCTAssertTrue(report.success)
        XCTAssertEqual(report.completed.count, 2)

        // Verify
        let outcome = Verifier().verify(report: report, rules: ["minCompleted:2"])
        XCTAssertTrue(outcome.passed)

        // Observe: drain the bus into metrics + timeline
        let events = await container.eventBus.replay()
        await container.metrics.ingest(events)
        await container.timeline.ingest(events)
        let toolExecs = await container.metrics.count(of: .toolExecuted)
        XCTAssertEqual(toolExecs, 2)
        let entries = await container.timeline.recent(100)
        XCTAssertFalse(entries.isEmpty)

        // Improve / close out
        await container.objectives.complete(objective.id)
        let done = await container.objectives.objective(objective.id)
        XCTAssertEqual(done?.status, .completed)
    }
}
