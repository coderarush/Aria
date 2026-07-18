import XCTest
@testable import Aria

final class TaskProgressPresentationTests: XCTestCase {
    func testTaskPresentationUsesFirstUnfinishedStepAndBoundedProgress() {
        var open = TaskStep(summary: "Open sources", executor: .tool("open_url"))
        open.status = .done
        let save = TaskStep(summary: "Save report", executor: .tool("save_note"))
        let share = TaskStep(summary: "Share summary", executor: .agent("Orion"))
        let plan = TaskPlan(goal: "Research a topic", steps: [open, save, share])

        let presentation = TaskProgressPresentation(plan: plan)

        XCTAssertEqual(presentation.completedCount, 1)
        XCTAssertEqual(presentation.totalCount, 3)
        XCTAssertEqual(presentation.currentStep, "Save report")
        XCTAssertEqual(presentation.fraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(presentation.statusText, "1 of 3 steps complete")
    }
}
