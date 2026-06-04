import XCTest
@testable import Aria

final class TaskPlanTests: XCTestCase {
    func testStepStatusTransitions() {
        var step = TaskStep(summary: "Open Notes", executor: .agent("Atlas"))
        XCTAssertEqual(step.status, .pending)
        step.status = .running
        step.result = "ok"
        step.status = .done
        XCTAssertEqual(step.status, .done)
        XCTAssertEqual(step.result, "ok")
    }
    func testPlanProgress() {
        var plan = TaskPlan(goal: "Test", steps: [
            TaskStep(summary: "a", executor: .tool("open_app")),
            TaskStep(summary: "b", executor: .agent("Orion")),
        ])
        plan.steps[0].status = .done
        XCTAssertEqual(plan.completedCount, 1)
        XCTAssertEqual(plan.total, 2)
        XCTAssertFalse(plan.isComplete)
        plan.steps[1].status = .done
        XCTAssertTrue(plan.isComplete)
    }
}
