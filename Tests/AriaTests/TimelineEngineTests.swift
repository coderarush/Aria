import XCTest
@testable import Aria

final class TimelineEngineTests: XCTestCase {

    // Fresh, isolated stores so the engine is deterministic and local-only.
    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, ContextCoordinator) {
        func url(_ tag: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("aria-tl-\(tag)-\(UUID().uuidString).json")
        }
        return (WorkJournal(fileURL: url("wj")),
                ActivityLog(url: url("al")),
                GoalEngine(fileURL: url("goal")),
                SessionMemoryStore(fileURL: url("sm")),
                ContextCoordinator())
    }

    private func engine(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, ContextCoordinator),
                        compressionWindow: TimeInterval = 90) -> TimelineEngine {
        TimelineEngine(timeline: Timeline(journal: s.0, activity: s.1),
                       activity: s.1, goals: s.2, sessions: s.3, context: s.4,
                       compressionWindow: compressionWindow)
    }

    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testTaskFinishedFromJournal() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "ship build", outcome: "green", ok: true,
                         project: "Aria", at: day)
        let evts = await engine(s).events(from: day.addingTimeInterval(-60),
                                          to: day.addingTimeInterval(60))
        XCTAssertEqual(evts.map(\.kind), [.taskFinished])
        XCTAssertEqual(evts.first?.title, "ship build")
        XCTAssertEqual(evts.first?.project, "Aria")
    }

    func testGoalCreatedAndAdvanced() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: day)!
        _ = await s.2.setNextAction(goalID: g.id, "wire timeline",
                                    now: day.addingTimeInterval(30))
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(60))
        XCTAssertEqual(Set(evts.map(\.kind)), [.goalCreated, .goalAdvanced])
        XCTAssertTrue(evts.allSatisfy { $0.title == "Ship V12" })
    }

    func testGoalNotAdvancedWhenUntouched() async {
        let s = makeStores()
        _ = await s.2.create(title: "Fresh", project: nil, now: day)
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(10))
        XCTAssertEqual(evts.map(\.kind), [.goalCreated])   // updatedAt == createdAt
    }

    func testResumeFromSessionMemory() async {
        let s = makeStores()
        await s.3.record(SessionSnapshot(project: "Aria", goal: "continue V12",
                                         progress: "engine done", date: day))
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(10),
                                          now: day.addingTimeInterval(5))
        XCTAssertEqual(evts.map(\.kind), [.resume])
        XCTAssertTrue(evts.first?.title.contains("continue V12") ?? false)
    }

    func testTestRunAndCommitMappedFromActivity() async {
        let s = makeStores()
        await s.1.record(tool: "run_tests", detail: "swift test", result: .ok("ok"), at: day)
        await s.1.record(tool: "shell", detail: "git commit -m feat", result: .ok("done"),
                         at: day.addingTimeInterval(5))
        await s.1.record(tool: "gmail_send", detail: "to: bob", result: .ok("sent"),
                         at: day.addingTimeInterval(10))
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(20))
        // gmail_send is not a meaningful timeline event — dropped.
        XCTAssertEqual(evts.map(\.kind), [.testRun, .commitCreated])
    }

    func testFocusChangeFromContext() async {
        let s = makeStores()
        await s.4.injectTestState(.build(activeApp: "Xcode", focusSince: day,
                                         clipboardSummary: nil, openFiles: [],
                                         recentActions: [], pendingSuggestion: nil,
                                         now: day.addingTimeInterval(120)))
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(200),
                                          now: day.addingTimeInterval(120))
        XCTAssertEqual(evts.map(\.kind), [.focusChange])
        XCTAssertEqual(evts.first?.title, "Xcode")
    }

    func testDedupeIdenticalEvents() async {
        let s = makeStores()
        // Same completed task recorded twice at the exact same instant.
        await s.0.record(kind: .task, title: "dup", outcome: "x", ok: true, at: day)
        await s.0.record(kind: .task, title: "dup", outcome: "x", ok: true, at: day)
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(10))
        XCTAssertEqual(evts.count, 1)
    }

    func testCompressionCollapsesRepeatRun() async {
        let s = makeStores()
        // Three "build" completions inside the compression window → one.
        for dt in [0.0, 20, 40] {
            await s.0.record(kind: .task, title: "build", outcome: "ok", ok: true,
                             at: day.addingTimeInterval(dt))
        }
        // A later "deploy" well outside the window → separate.
        await s.0.record(kind: .task, title: "deploy", outcome: "ok", ok: true,
                         at: day.addingTimeInterval(300))
        let evts = await engine(s, compressionWindow: 90)
            .events(from: day.addingTimeInterval(-10), to: day.addingTimeInterval(400))
        XCTAssertEqual(evts.map(\.title), ["build", "deploy"])
    }

    func testChronologicalOrder() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "second", outcome: "", ok: true,
                         at: day.addingTimeInterval(50))
        _ = await s.2.create(title: "first", project: nil, now: day)
        let evts = await engine(s).events(from: day.addingTimeInterval(-10),
                                          to: day.addingTimeInterval(100))
        XCTAssertEqual(evts.map(\.title), ["first", "second"])
    }

    func testRecentNewestFirstLimited() async {
        let s = makeStores()
        for i in 0..<5 {
            await s.0.record(kind: .task, title: "t\(i)", outcome: "", ok: true,
                             at: day.addingTimeInterval(Double(i) * 10))
        }
        let recent = await engine(s).recent(2, now: day.addingTimeInterval(100))
        XCTAssertEqual(recent.map(\.title), ["t4", "t3"])
    }

    func testSummarizeGroupsByDayWithCounts() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "a", outcome: "", ok: true, at: day)
        await s.0.record(kind: .task, title: "b", outcome: "", ok: false, at: day.addingTimeInterval(60))
        let text = await engine(s).summarize(from: day.addingTimeInterval(-10),
                                             to: day.addingTimeInterval(120))
        XCTAssertTrue(text.contains("a"))
        XCTAssertTrue(text.contains("b"))
        XCTAssertFalse(text.isEmpty)
    }

    func testPruneDropsBeforeHorizon() async {
        let s = makeStores()
        await s.0.record(kind: .task, title: "old", outcome: "", ok: true, at: day)
        await s.0.record(kind: .task, title: "new", outcome: "", ok: true,
                         at: day.addingTimeInterval(1000))
        let e = engine(s)
        await e.prune(before: day.addingTimeInterval(500))
        let evts = await e.events(from: day.addingTimeInterval(-10),
                                  to: day.addingTimeInterval(2000))
        XCTAssertEqual(evts.map(\.title), ["new"])
    }

    func testResumeBriefSurfacesActiveGoal() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: day)!
        _ = await s.2.setNextAction(goalID: g.id, "wire timeline", now: day)
        let brief = await engine(s).resumeBrief(project: "aria", now: day.addingTimeInterval(60))
        XCTAssertTrue(brief.contains("Ship V12"))
        XCTAssertTrue(brief.contains("wire timeline"))
    }

    func testResumeBriefIsFast() async {
        let s = makeStores()
        _ = await s.2.create(title: "G", project: nil, now: day)
        let start = Date()
        _ = await engine(s).resumeBrief(now: day)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)   // resume path <2s
    }
}
