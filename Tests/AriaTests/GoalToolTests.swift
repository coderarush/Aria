import XCTest
@testable import Aria

final class GoalToolTests: XCTestCase {

    private func tempEngine() -> GoalEngine {
        GoalEngine(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-goaltool-\(UUID().uuidString).json"))
    }

    func testCreateMakesAGoal() async throws {
        let engine = tempEngine()
        let tool = GoalTool(engine: engine)
        let r = try await tool.run(input: ["action": "create", "title": "Ship Aria V12", "project": "Aria"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("Ship Aria V12"))
        let active = await engine.active()
        XCTAssertEqual(active.map(\.title), ["Ship Aria V12"])
    }

    func testUnknownActionFails() async throws {
        let tool = GoalTool(engine: tempEngine())
        let r = try await tool.run(input: ["action": "frobnicate"])
        XCTAssertFalse(r.success)
    }

    func testContinueWithNoGoals() async throws {
        let tool = GoalTool(engine: tempEngine())
        let r = try await tool.run(input: ["action": "continue"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.lowercased().contains("no active goal"))
    }

    func testAdvanceSetsNextActionByTitleMatch() async throws {
        let engine = tempEngine()
        _ = await engine.create(title: "Ship Aria V12", project: "Aria")
        let tool = GoalTool(engine: engine)
        let r = try await tool.run(input: ["action": "advance", "goal": "ship", "next": "wire GoalTool"])
        XCTAssertTrue(r.success)
        let g = await engine.active().first
        XCTAssertEqual(g?.nextAction, "wire GoalTool")
    }

    func testAdvanceCompleteMarksDone() async throws {
        let engine = tempEngine()
        _ = await engine.create(title: "Tiny goal", project: nil)
        let tool = GoalTool(engine: engine)
        let r = try await tool.run(input: ["action": "advance", "goal": "tiny", "done": "true"])
        XCTAssertTrue(r.success)
        let active = await engine.active()
        XCTAssertTrue(active.isEmpty)        // completed → no longer active
    }

    func testBlockersListsOpenBlockers() async throws {
        let engine = tempEngine()
        let g = await engine.create(title: "Launch", project: nil)!
        _ = await engine.addBlocker(goalID: g.id, "notarization")
        let tool = GoalTool(engine: engine)
        let r = try await tool.run(input: ["action": "blockers"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("notarization"))
    }

    func testAdvanceUnknownGoalFails() async throws {
        let tool = GoalTool(engine: tempEngine())
        let r = try await tool.run(input: ["action": "advance", "goal": "nonexistent", "next": "x"])
        XCTAssertFalse(r.success)
    }
}
