import XCTest
@testable import Aria

final class Part6OpsTests: XCTestCase {

    // MARK: - DogfoodEngine (§120)

    func testFrictionReportBuckets() async {
        let engine = DogfoodEngine()
        await engine.logFriction(.slow, "planning step")
        await engine.logFriction(.broken, "gmail tool")
        await engine.logFriction(.broken, "calendar tool")
        let report = await engine.report()
        XCTAssertEqual(report.slow, ["planning step"])
        XCTAssertEqual(report.broken.count, 2)
        XCTAssertTrue(report.confusing.isEmpty)
    }

    // MARK: - LatencyBudget (§119)

    func testLatencyWithinBudget() {
        let budget = LatencyBudget()
        XCTAssertTrue(budget.within(.intent, measured: 0.4))
        XCTAssertFalse(budget.within(.intent, measured: 0.9))
    }

    func testLatencyImprovementDetected() {
        let budget = LatencyBudget()
        XCTAssertTrue(budget.improved(.boot, previous: 2.0, current: 1.5))
        XCTAssertFalse(budget.improved(.boot, previous: 1.5, current: 1.8))
    }

    // MARK: - ReleaseEngine (§122)

    func testPromoteRollbackKillAndGate() async {
        let engine = ReleaseEngine(channel: .alpha)
        await engine.promote(to: .beta)
        var channel = await engine.channel
        XCTAssertEqual(channel, .beta)
        await engine.rollback(to: .alpha)
        channel = await engine.channel
        XCTAssertEqual(channel, .alpha)

        await engine.setGate("newPlanner", true)
        let open = await engine.isGateOpen("newPlanner")
        XCTAssertTrue(open)

        await engine.killSwitch()
        let live = await engine.isLive()
        XCTAssertFalse(live)
    }

    // MARK: - GlassReadiness (§123)

    func testGlassReadinessThreshold() {
        let readiness = GlassReadiness()
        let strong = GlassReadiness.Scores(portability: 0.9, latency: 0.85,
                                           contextQuality: 0.9, presenceUsefulness: 0.8)
        XCTAssertTrue(readiness.isReady(strong))
        let weak = GlassReadiness.Scores(portability: 0.5, latency: 0.4,
                                         contextQuality: 0.6, presenceUsefulness: 0.3)
        XCTAssertFalse(readiness.isReady(weak))
    }
}
