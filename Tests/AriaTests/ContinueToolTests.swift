import XCTest
@testable import Aria

final class ContinueToolTests: XCTestCase {

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, ContextCoordinator) {
        func url(_ tag: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("aria-cont-\(tag)-\(UUID().uuidString).json")
        }
        return (WorkJournal(fileURL: url("wj")), ActivityLog(url: url("al")),
                GoalEngine(fileURL: url("goal")), SessionMemoryStore(fileURL: url("sm")),
                ContextCoordinator())
    }

    private func tool(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, ContextCoordinator),
                      now: Date) -> ContinueTool {
        let engine = TimelineEngine(timeline: Timeline(journal: s.0, activity: s.1),
                                    activity: s.1, goals: s.2, sessions: s.3, context: s.4)
        return ContinueTool(engine: engine, now: { now })
    }

    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testContinueSurfacesActiveGoal() async throws {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: day)!
        _ = await s.2.setNextAction(goalID: g.id, "wire timeline", now: day)
        let r = try await tool(s, now: day.addingTimeInterval(60)).run(input: ["project": "aria"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("Ship V12"))
        XCTAssertTrue(r.output.contains("wire timeline"))
    }

    func testContinueFallsBackToSession() async throws {
        let s = makeStores()
        await s.3.record(SessionSnapshot(project: "Aria", goal: "finish engine",
                                         nextStep: "ship it", date: day))
        let r = try await tool(s, now: day.addingTimeInterval(60)).run(input: [:])
        XCTAssertTrue(r.output.contains("finish engine"))
    }

    func testContinueNothingInProgress() async throws {
        let s = makeStores()
        let r = try await tool(s, now: day).run(input: [:])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.lowercased().contains("nothing in progress"))
    }

    func testRecentDoesNotRepeatTitles() async throws {
        let s = makeStores()
        // A goal that is created AND advanced surfaces two events with the same
        // title — the Recent list must not show it twice.
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: day)!
        _ = await s.2.setNextAction(goalID: g.id, "notarize", now: day.addingTimeInterval(20))
        let r = try await tool(s, now: day.addingTimeInterval(60)).run(input: [:])
        let occurrences = r.output.components(separatedBy: "Ship V12").count - 1
        // Once in the "Continue:" line, at most once more in Recent.
        XCTAssertLessThanOrEqual(occurrences, 2)
        let recentSection = r.output.components(separatedBy: "Recent:").last ?? ""
        XCTAssertEqual(recentSection.components(separatedBy: "Ship V12").count - 1, 1)
    }

    func testContinueListsRecentWork() async throws {
        let s = makeStores()
        _ = await s.2.create(title: "Goal", project: nil, now: day)
        await s.0.record(kind: .task, title: "ran the suite", outcome: "green", ok: true,
                         at: day.addingTimeInterval(10))
        let r = try await tool(s, now: day.addingTimeInterval(60)).run(input: [:])
        XCTAssertTrue(r.output.contains("ran the suite"))
    }
}
