import XCTest
@testable import Aria

final class StatusToolTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testStatusReportsNextAndLoops() async throws {
        func url(_ s: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("aria-st-\(s)-\(UUID().uuidString).json") }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al, goals: g, sessions: sm, context: ContextCoordinator())
        let goal = await g.create(title: "Ship V12", project: "Aria", now: t)!
        _ = await g.setNextAction(goalID: goal.id, "notarize", now: t)
        let tool = StatusTool(briefing: ExecutiveBriefing(goals: g, timeline: tl, context: ContextCoordinator()),
                              now: { [t] in t.addingTimeInterval(60) })
        let r = try await tool.run(input: [:])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("Ship V12"))
        XCTAssertTrue(r.output.contains("notarize"))
        XCTAssertTrue(r.output.contains("confidence"))
    }
}
