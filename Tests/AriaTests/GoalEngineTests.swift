import XCTest
@testable import Aria

final class GoalEngineTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-goals-\(UUID().uuidString).json")
    }

    // MARK: create

    func testCreateReturnsActiveGoalAndIsRecallable() async {
        let engine = GoalEngine(fileURL: tempURL())
        let goal = await engine.create(title: "Ship Aria V12", project: "Aria")!
        XCTAssertEqual(goal.title, "Ship Aria V12")
        XCTAssertEqual(goal.project, "Aria")
        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(goal.progress, 0)
        let fetched = await engine.goal(id: goal.id)
        XCTAssertEqual(fetched?.title, "Ship Aria V12")
    }

    func testCreateRejectsBlankTitle() async {
        let engine = GoalEngine(fileURL: tempURL())
        let goal = await engine.create(title: "   ", project: nil)
        XCTAssertNil(goal)
        let active = await engine.active()
        XCTAssertTrue(active.isEmpty)
    }

    // MARK: milestones + progress

    func testProgressIsFractionOfCompletedMilestones() async {
        let engine = GoalEngine(fileURL: tempURL())
        let g = await engine.create(title: "G", project: nil)!
        let m1 = await engine.addMilestone(goalID: g.id, title: "design")!
        _ = await engine.addMilestone(goalID: g.id, title: "build")
        var cur = await engine.goal(id: g.id)
        XCTAssertEqual(cur?.progress, 0)
        _ = await engine.completeMilestone(goalID: g.id, milestoneID: m1.id)
        cur = await engine.goal(id: g.id)
        XCTAssertEqual(cur?.progress, 0.5)        // 1 of 2 done
    }

    func testGoalWithNoMilestonesHasZeroProgressUntilCompleted() async {
        let engine = GoalEngine(fileURL: tempURL())
        let g = await engine.create(title: "G", project: nil)!
        XCTAssertEqual(g.progress, 0)
        _ = await engine.complete(goalID: g.id)
        let done = await engine.goal(id: g.id)
        XCTAssertEqual(done?.progress, 1)
        XCTAssertEqual(done?.status, .done)
    }

    func testAdvanceBumpsUpdatedAt() async {
        let engine = GoalEngine(fileURL: tempURL())
        let t0 = Date(timeIntervalSince1970: 1_000)
        let g = await engine.create(title: "G", project: nil, now: t0)!
        XCTAssertEqual(g.updatedAt, t0)
        let t1 = Date(timeIntervalSince1970: 2_000)
        _ = await engine.setNextAction(goalID: g.id, "call the bank", now: t1)
        let cur = await engine.goal(id: g.id)
        XCTAssertEqual(cur?.nextAction, "call the bank")
        XCTAssertEqual(cur?.updatedAt, t1)
    }

    // MARK: blockers

    func testBlockersAddClearAndAggregate() async {
        let engine = GoalEngine(fileURL: tempURL())
        let a = await engine.create(title: "A", project: nil)!
        let b = await engine.create(title: "B", project: nil)!
        _ = await engine.addBlocker(goalID: a.id, "waiting on API key")
        _ = await engine.addBlocker(goalID: b.id, "needs design review")
        let all = await engine.blockers()
        XCTAssertEqual(all.count, 2)
        _ = await engine.clearBlocker(goalID: a.id, "waiting on API key")
        let after = await engine.blockers()
        XCTAssertEqual(after.map(\.blocker), ["needs design review"])
    }

    func testDuplicateBlockerNotAddedTwice() async {
        let engine = GoalEngine(fileURL: tempURL())
        let g = await engine.create(title: "G", project: nil)!
        _ = await engine.addBlocker(goalID: g.id, "same")
        _ = await engine.addBlocker(goalID: g.id, "same")
        let cur = await engine.goal(id: g.id)
        XCTAssertEqual(cur?.blockers, ["same"])
    }

    // MARK: active ordering + lifecycle

    func testActiveExcludesDoneAndArchivedNewestFirst() async {
        let engine = GoalEngine(fileURL: tempURL())
        let t = Date(timeIntervalSince1970: 1_000)
        let a = await engine.create(title: "A", project: nil, now: t)!
        let b = await engine.create(title: "B", project: nil, now: t.addingTimeInterval(10))!
        _ = await engine.complete(goalID: a.id)
        let active = await engine.active()
        XCTAssertEqual(active.map(\.title), ["B"])
        _ = await engine.archive(goalID: b.id)
        let none = await engine.active()
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: continue digest

    func testContinueDigestSurfacesTopGoalNextActionAndBlockers() async {
        let engine = GoalEngine(fileURL: tempURL())
        let t = Date(timeIntervalSince1970: 1_000)
        _ = await engine.create(title: "old", project: "Aria", now: t)
        let g = await engine.create(title: "Ship V12", project: "Aria",
                                    now: t.addingTimeInterval(10))!
        _ = await engine.setNextAction(goalID: g.id, "wire GoalEngine",
                                       now: t.addingTimeInterval(20))
        _ = await engine.addBlocker(goalID: g.id, "notarization")
        let digest = await engine.continueDigest(project: "aria")
        XCTAssertNotNil(digest)
        XCTAssertTrue(digest!.contains("Ship V12"))
        XCTAssertTrue(digest!.contains("wire GoalEngine"))
        XCTAssertTrue(digest!.contains("notarization"))
    }

    func testContinueDigestNilWhenNoActiveGoals() async {
        let engine = GoalEngine(fileURL: tempURL())
        let digest = await engine.continueDigest(project: nil)
        XCTAssertNil(digest)
    }

    // MARK: persistence

    func testGoalsPersistAcrossInstances() async {
        let url = tempURL()
        let e1 = GoalEngine(fileURL: url)
        let g = await e1.create(title: "Durable", project: "Aria")!
        _ = await e1.addBlocker(goalID: g.id, "blk")
        let e2 = GoalEngine(fileURL: url)
        let reloaded = await e2.goal(id: g.id)
        XCTAssertEqual(reloaded?.title, "Durable")
        XCTAssertEqual(reloaded?.blockers, ["blk"])
    }

    func testCapEvictsOldestGoals() async {
        let engine = GoalEngine(fileURL: tempURL(), cap: 2)
        let t = Date(timeIntervalSince1970: 1_000)
        let a = await engine.create(title: "A", project: nil, now: t)!
        _ = await engine.create(title: "B", project: nil, now: t.addingTimeInterval(1))
        _ = await engine.create(title: "C", project: nil, now: t.addingTimeInterval(2))
        let gone = await engine.goal(id: a.id)
        XCTAssertNil(gone)                         // oldest evicted
        let active = await engine.active()
        XCTAssertEqual(active.map(\.title).sorted(), ["B", "C"])
    }
}
