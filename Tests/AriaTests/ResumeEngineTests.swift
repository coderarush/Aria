import XCTest
@testable import Aria

final class ResumeEngineTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, TaskStore) {
        func url(_ s: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("aria-re-\(s)-\(UUID().uuidString).json") }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al, goals: g, sessions: sm, context: ContextCoordinator())
        let ts = TaskStore(url: url("task"))
        return (wj, al, g, sm, tl, ts)
    }
    private func engine(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, TaskStore)) -> ResumeEngine {
        ResumeEngine(tasks: s.5, goals: s.2, timeline: s.4)
    }
    private func task(goal: String) -> PersistedTask {
        PersistedTask(goal: goal, steps: [
            .init(summary: "step 1", kind: "tool", name: "a", input: [:], status: "done", result: ""),
            .init(summary: "step 2", kind: "tool", name: "b", input: [:], status: "pending", result: "")
        ], lastOutput: "", updatedAt: t)
    }

    func testRestoreWithInFlightTask() async {
        let s = makeStores()
        await s.5.save(task(goal: "Ship V12"))
        let st = await engine(s).restore(now: t.addingTimeInterval(60))
        XCTAssertEqual(st.inFlightTask, "Ship V12")
        XCTAssertEqual(st.unfinishedSteps, 1)
        XCTAssertEqual(st.resumeIndex, 1)
        XCTAssertTrue(st.suggestedNext?.lowercased().contains("resume") ?? false)
    }

    func testRestoreWithoutTaskUsesGoalNext() async {
        let s = makeStores()
        let g = await s.2.create(title: "Write report", project: "Aria", now: t)!
        _ = await s.2.setNextAction(goalID: g.id, "draft intro", now: t)
        let st = await engine(s).restore(now: t.addingTimeInterval(60))
        XCTAssertNil(st.inFlightTask)
        XCTAssertEqual(st.suggestedNext, "draft intro")
        XCTAssertEqual(st.openLoops, ["Write report"])
    }

    func testRecentChanges() async {
        let s = makeStores()
        _ = await s.2.create(title: "G", project: "Aria", now: t)
        await s.0.record(kind: .task, title: "shipped audit", outcome: "", ok: true, project: "Aria", at: t.addingTimeInterval(10))
        let st = await engine(s).restore(now: t.addingTimeInterval(60))
        XCTAssertTrue(st.recentChanges.contains { $0.contains("shipped audit") })
    }

    func testTextMentionsResume() async {
        let s = makeStores()
        await s.5.save(task(goal: "Ship V12"))
        let st = await engine(s).restore(now: t.addingTimeInterval(60))
        XCTAssertTrue(st.text().contains("Ship V12"))
    }

    func testRestoreIsFast() async {
        let s = makeStores()
        await s.5.save(task(goal: "G"))
        let start = Date()
        _ = await engine(s).restore(now: t)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }
}
