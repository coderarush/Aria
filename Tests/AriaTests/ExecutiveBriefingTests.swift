import XCTest
@testable import Aria

final class ExecutiveBriefingTests: XCTestCase {

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, ContextCoordinator) {
        func url(_ t: String) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("aria-eb-\(t)-\(UUID().uuidString).json")
        }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let ctx = ContextCoordinator()
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al, goals: g, sessions: sm, context: ctx)
        return (wj, al, g, sm, tl, ctx)
    }
    private func briefing(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine, ContextCoordinator)) -> ExecutiveBriefing {
        ExecutiveBriefing(goals: s.2, timeline: s.4, context: s.5)
    }
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testOpenLoopsAndNextAction() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        _ = await s.2.setNextAction(goalID: g.id, "notarize", now: t.addingTimeInterval(10))
        let out = await briefing(s).compose(now: t.addingTimeInterval(60))
        XCTAssertEqual(out.openLoops, ["Ship V12"])
        XCTAssertEqual(out.nextAction, "notarize")
    }

    func testBlockedSurfacesAsRisk() async {
        let s = makeStores()
        let g = await s.2.create(title: "Launch", project: "Aria", now: t)!
        _ = await s.2.addBlocker(goalID: g.id, "notarization", now: t.addingTimeInterval(5))
        let out = await briefing(s).compose(now: t.addingTimeInterval(60))
        XCTAssertTrue(out.blocked.contains { $0.contains("notarization") })
        XCTAssertTrue(out.risks.contains { $0.contains("notarization") })
    }

    func testRecentProgressFromTimeline() async {
        let s = makeStores()
        _ = await s.2.create(title: "G", project: "Aria", now: t)
        await s.0.record(kind: .task, title: "fixed audio", outcome: "", ok: true, project: "Aria", at: t.addingTimeInterval(20))
        let out = await briefing(s).compose(now: t.addingTimeInterval(60))
        XCTAssertTrue(out.recentProgress.contains { $0.contains("fixed audio") })
    }

    func testConfidenceReflectsCompleteness() async {
        let s = makeStores()
        let empty = await briefing(s).compose(now: t)
        XCTAssertEqual(empty.confidence, 0)            // nothing populated
        let g = await s.2.create(title: "G", project: "Aria", now: t)!
        _ = await s.2.setNextAction(goalID: g.id, "do x", now: t)
        let some = await briefing(s).compose(now: t.addingTimeInterval(60))
        XCTAssertGreaterThan(some.confidence, 0)
        XCTAssertLessThanOrEqual(some.confidence, 1)
    }

    func testTextIsNonEmptyAndShort() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        _ = await s.2.setNextAction(goalID: g.id, "notarize", now: t)
        let out = await briefing(s).compose(now: t.addingTimeInterval(60))
        let text = out.text()
        XCTAssertTrue(text.contains("Ship V12"))
        XCTAssertTrue(text.contains("notarize"))
        XCTAssertLessThan(text.count, 1200)
    }

    func testProjectScoped() async {
        let s = makeStores()
        _ = await s.2.create(title: "Aria goal", project: "Aria", now: t)
        _ = await s.2.create(title: "Other goal", project: "Other", now: t.addingTimeInterval(5))
        let out = await briefing(s).compose(project: "aria", now: t.addingTimeInterval(60))
        XCTAssertEqual(out.openLoops, ["Aria goal"])
    }
}
