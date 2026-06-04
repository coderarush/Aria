import XCTest
@testable import Aria

final class KeyRotatorTests: XCTestCase {
    func testReservesFirstAvailable() {
        let t = Date(timeIntervalSince1970: 0)
        let r = KeyRotator(keys: ["k1", "k2"], now: { t })
        XCTAssertEqual(r.reserve(), "k1")
    }

    func testRoutesAroundPenalizedKey() {
        let t = Date(timeIntervalSince1970: 0)
        let r = KeyRotator(keys: ["k1", "k2"], now: { t })
        r.penalize("k1", seconds: 90)
        XCTAssertEqual(r.reserve(), "k2")
    }

    func testNilWhenAllBlockedThenRecovers() {
        var t = Date(timeIntervalSince1970: 0)
        let r = KeyRotator(keys: ["k1"], now: { t })
        r.penalize("k1", seconds: 90)
        XCTAssertNil(r.reserve())
        XCTAssertEqual(r.waitTime(), 90, accuracy: 1)
        t = Date(timeIntervalSince1970: 91)
        XCTAssertEqual(r.reserve(), "k1")
    }

    func testUpdateDropsStaleCooldowns() {
        let t = Date(timeIntervalSince1970: 0)
        let r = KeyRotator(keys: ["k1", "k2"], now: { t })
        r.penalize("k1")
        r.update(keys: ["k2", "k3"])      // k1 removed
        XCTAssertEqual(r.reserve(), "k2") // no stale k1 cooldown lingering
    }

    func testEmpty() {
        XCTAssertTrue(KeyRotator(keys: []).isEmpty)
        XCTAssertNil(KeyRotator(keys: []).reserve())
    }
}
