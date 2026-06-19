import XCTest
@testable import Aria

final class Part6ProductTests: XCTestCase {

    // MARK: - DelightEngine (§111)

    func testDelightNeverInterruptsOrGamifies() {
        let engine = DelightEngine()
        XCTAssertFalse(engine.interrupts)
        XCTAssertFalse(engine.manipulates)
        XCTAssertFalse(engine.gamifies)
        let delight = engine.note("continued where you left off")
        XCTAssertFalse(delight.message.isEmpty)
    }

    // MARK: - HabitEngine (§112)

    func testHabitScoreFromBehavior() async {
        let engine = HabitEngine()
        await engine.recordSession(returning: true)
        await engine.recordSession(returning: true)
        await engine.recordObjective(completed: true)
        await engine.recordObjective(completed: false)
        await engine.recordDelegation()
        let score = await engine.score()
        XCTAssertEqual(score.returnRate, 1.0, accuracy: 1e-9)
        XCTAssertEqual(score.completionRate, 0.5, accuracy: 1e-9)
    }

    // MARK: - FeedbackEngine (§114)

    func testFeedbackInsightsFromBehavior() async {
        let engine = FeedbackEngine()
        await engine.record(.accept)
        await engine.record(.accept)
        await engine.record(.reject)
        let insights = await engine.insights()
        XCTAssertEqual(insights.accepts, 2)
        XCTAssertEqual(insights.acceptanceRate, 2.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: - AnalyticsEngine (§121) — metadata only

    func testAnalyticsCountsMetadataOnly() async {
        let engine = AnalyticsEngine()
        await engine.track(.continuation)
        await engine.track(.execution)
        await engine.track(.execution)
        await engine.track(.closure)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.executions, 2)
        XCTAssertEqual(snapshot.continuations, 1)
        XCTAssertEqual(snapshot.closures, 1)
    }
}
