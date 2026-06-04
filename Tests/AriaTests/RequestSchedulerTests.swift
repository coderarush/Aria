import XCTest
@testable import Aria

final class RequestSchedulerTests: XCTestCase {
    func testPicksAModelUnderLimit() {
        let t = Date(timeIntervalSince1970: 0)
        let s = RequestScheduler(models: ["a", "b"], perMinuteLimit: 2, now: { t })
        XCTAssertEqual(s.reserve(), "a")
        XCTAssertEqual(s.reserve(), "a")
        XCTAssertEqual(s.reserve(), "b")
    }

    func testReturnsNilAndWaitWhenAllMaxed() {
        let t = Date(timeIntervalSince1970: 0)
        let s = RequestScheduler(models: ["a"], perMinuteLimit: 1, now: { t })
        XCTAssertEqual(s.reserve(), "a")
        XCTAssertNil(s.reserve())
        XCTAssertEqual(s.waitTime(), 60, accuracy: 0.2)
    }

    func testFreesUpAfterWindowPasses() {
        var t = Date(timeIntervalSince1970: 0)
        let s = RequestScheduler(models: ["a"], perMinuteLimit: 1, now: { t })
        XCTAssertEqual(s.reserve(), "a")
        t = Date(timeIntervalSince1970: 61)
        XCTAssertEqual(s.reserve(), "a")
    }

    func testRecordCountsAgainstBucket() {
        let t = Date(timeIntervalSince1970: 0)
        let s = RequestScheduler(models: ["a"], perMinuteLimit: 1, now: { t })
        s.record("a")
        XCTAssertNil(s.reserve())   // bucket already full from record()
    }

    // C1 regression: a server 429 (penalize) must route around the model and, when
    // all are penalized, report a real wait — not let the caller hot-spin and fail.
    func testPenalizedModelIsSkippedThenPaces() {
        var t = Date(timeIntervalSince1970: 0)
        let s = RequestScheduler(models: ["a", "b"], perMinuteLimit: 5, now: { t })
        s.penalize("a", seconds: 30)
        XCTAssertEqual(s.reserve(), "b")        // routes around penalized a
        s.penalize("b", seconds: 30)
        XCTAssertNil(s.reserve())               // both rate-limited
        XCTAssertEqual(s.waitTime(), 30, accuracy: 1.0)   // real pacing, not 0
        t = Date(timeIntervalSince1970: 31)
        XCTAssertNotNil(s.reserve())            // cooldown passed → available again
    }
}
