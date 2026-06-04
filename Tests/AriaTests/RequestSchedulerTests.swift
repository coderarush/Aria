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
}
