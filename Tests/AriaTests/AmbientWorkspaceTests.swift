import XCTest
@testable import Aria

final class AmbientWorkspaceTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, ContextCoordinator) {
        func url(_ s: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("aria-aw-\(s)-\(UUID().uuidString).json") }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let ctx = ContextCoordinator()
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al, goals: g, sessions: sm, context: ctx)
        return (wj, al, g, sm, tl, ctx)
    }
    private func ws(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, ContextCoordinator)) -> AmbientWorkspace {
        AmbientWorkspace(goals: s.2, timeline: s.4, context: s.5)
    }

    func testTopGoalProgressAndNext() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        let m = await s.2.addMilestone(goalID: g.id, title: "build", now: t)!
        _ = await s.2.addMilestone(goalID: g.id, title: "ship", now: t)
        _ = await s.2.completeMilestone(goalID: g.id, milestoneID: m.id, now: t)
        _ = await s.2.setNextAction(goalID: g.id, "notarize", now: t)
        let snap = await ws(s).snapshot(now: t.addingTimeInterval(60))
        XCTAssertEqual(snap.goal, "Ship V12")
        XCTAssertEqual(snap.progress, 0.5)
        XCTAssertEqual(snap.nextAction, "notarize")
        XCTAssertEqual(snap.openLoops, ["Ship V12"])
    }

    func testFocusFromContext() async {
        let s = makeStores()
        await s.5.injectTestState(.build(activeApp: "Xcode", focusSince: t, clipboardSummary: nil,
                                         openFiles: [], recentActions: [], pendingSuggestion: nil,
                                         now: t.addingTimeInterval(120)))
        let snap = await ws(s).snapshot(now: t.addingTimeInterval(120))
        XCTAssertEqual(snap.focus, "Xcode")
    }

    func testRecentActivity() async {
        let s = makeStores()
        _ = await s.2.create(title: "G", project: "Aria", now: t)
        await s.0.record(kind: .task, title: "ran tests", outcome: "", ok: true, project: "Aria", at: t.addingTimeInterval(10))
        let snap = await ws(s).snapshot(now: t.addingTimeInterval(60))
        XCTAssertTrue(snap.recentActivity.contains { $0.contains("ran tests") })
    }

    func testEmptyIsLowConfidenceButValid() async {
        let s = makeStores()
        let snap = await ws(s).snapshot(now: t)
        XCTAssertNil(snap.goal)
        XCTAssertEqual(snap.confidence, 0)
        XCTAssertTrue(snap.openLoops.isEmpty)
    }
}
