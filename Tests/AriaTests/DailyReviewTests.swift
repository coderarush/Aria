import XCTest
@testable import Aria

final class DailyReviewTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    // 2023-11-14 22:13:20 UTC — comfortably mid-day in UTC.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine) {
        func url(_ s: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("aria-dr-\(s)-\(UUID().uuidString).json") }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al, goals: g, sessions: sm, context: ContextCoordinator())
        return (wj, al, g, sm, tl)
    }
    private func engine(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine)) -> DailyReviewEngine {
        DailyReviewEngine(timeline: s.4, goals: s.2)
    }

    func testWinsFromTodaysCompletedTasks() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "shipped MemoryGraph", outcome: "", ok: true, project: "Aria", at: now.addingTimeInterval(-600))
        await s.0.record(kind: .task, title: "broke build", outcome: "", ok: false, project: "Aria", at: now.addingTimeInterval(-300))
        let r = await engine(s).review(now: now, calendar: utc)
        XCTAssertTrue(r.wins.contains { $0.contains("shipped MemoryGraph") })
        XCTAssertFalse(r.wins.contains { $0.contains("broke build") })   // failures aren't wins
    }

    func testProgressFromGoalAdvances() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: now.addingTimeInterval(-600))!
        _ = await s.2.setNextAction(goalID: g.id, "notarize", now: now.addingTimeInterval(-120))
        let r = await engine(s).review(now: now, calendar: utc)
        XCTAssertTrue(r.progress.contains { $0.contains("Ship V12") })
    }

    func testUnfinishedFromActiveGoals() async {
        let s = makeStores()
        let g = await s.2.create(title: "Launch", project: "Aria", now: now.addingTimeInterval(-600))!
        _ = await s.2.setNextAction(goalID: g.id, "record film", now: now.addingTimeInterval(-600))
        let r = await engine(s).review(now: now, calendar: utc)
        XCTAssertTrue(r.unfinished.contains { $0.contains("Launch") })
    }

    func testTomorrowSuggestsNextActions() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: now.addingTimeInterval(-600))!
        _ = await s.2.setNextAction(goalID: g.id, "notarize build", now: now.addingTimeInterval(-600))
        let r = await engine(s).review(now: now, calendar: utc)
        XCTAssertTrue(r.tomorrow.contains { $0.contains("notarize build") })
    }

    func testTextHasSections() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "did thing", outcome: "", ok: true, project: "Aria", at: now.addingTimeInterval(-600))
        let r = await engine(s).review(now: now, calendar: utc)
        let text = r.text()
        XCTAssertTrue(text.contains("Wins") || text.contains("did thing"))
        XCTAssertFalse(text.isEmpty)
    }

    func testEmptyDayIsReadable() async {
        let s = makeStores()
        let r = await engine(s).review(now: now, calendar: utc)
        XCTAssertFalse(r.text().isEmpty)
    }
}
