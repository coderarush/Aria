import XCTest
@testable import Aria

final class Part6QualityTimeTests: XCTestCase {

    // MARK: - ExecutionQuality (§110)

    func testPerfectExecutionScoresHigh() async {
        let quality = ExecutionQuality()
        for _ in 0..<5 { await quality.record(success: true, verified: true, corrected: false, retries: 0) }
        let score = await quality.score()
        XCTAssertEqual(score.successRate, 1.0, accuracy: 1e-9)
        XCTAssertGreaterThan(score.composite, 0.9)
    }

    func testCorrectionsAndRetriesLowerScore() async {
        let quality = ExecutionQuality()
        await quality.record(success: true, verified: false, corrected: true, retries: 3)
        let score = await quality.score()
        XCTAssertEqual(score.correctionRate, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(score.composite, 0.6)
    }

    // MARK: - TimeEngine (§113)

    func testTimeAccumulates() async {
        let engine = TimeEngine()
        await engine.record(minutesSaved: 4, switchesAvoided: 2)
        await engine.record(minutesSaved: 3, switchesAvoided: 1)
        let total = await engine.totalMinutesSaved()
        XCTAssertEqual(total, 7, accuracy: 1e-9)
    }

    func testSummaryShownOnlyIfMeaningful() async {
        let small = TimeEngine()
        await small.record(minutesSaved: 1, switchesAvoided: 0)
        let smallSummary = await small.summary()
        XCTAssertNil(smallSummary)

        let big = TimeEngine()
        await big.record(minutesSaved: 30, switchesAvoided: 5)
        let bigSummary = await big.summary()
        XCTAssertNotNil(bigSummary)
        XCTAssertTrue(bigSummary!.contains("30"))
    }
}
