import XCTest
@testable import Aria

final class DoubleTapDetectorTests: XCTestCase {

    func testSecondTapWithinWindowFires() {
        var d = DoubleTapDetector(window: 0.4)
        let t = Date()
        XCTAssertFalse(d.registerTap(at: t))                          // first tap, nothing yet
        XCTAssertTrue(d.registerTap(at: t.addingTimeInterval(0.3)))   // double within window
    }

    func testSlowSecondTapDoesNotFire() {
        var d = DoubleTapDetector(window: 0.4)
        let t = Date()
        XCTAssertFalse(d.registerTap(at: t))
        XCTAssertFalse(d.registerTap(at: t.addingTimeInterval(0.6))) // gap too large
    }

    func testTripleTapFiresOnlyOnce() {
        var d = DoubleTapDetector(window: 0.4)
        let t = Date()
        XCTAssertFalse(d.registerTap(at: t))
        XCTAssertTrue(d.registerTap(at: t.addingTimeInterval(0.2)))   // pair fires
        XCTAssertFalse(d.registerTap(at: t.addingTimeInterval(0.3)))  // third is a fresh lone tap
    }

    func testConsecutivePairsBothFire() {
        var d = DoubleTapDetector(window: 0.4)
        let t = Date()
        _ = d.registerTap(at: t)
        XCTAssertTrue(d.registerTap(at: t.addingTimeInterval(0.2)))   // first pair
        _ = d.registerTap(at: t.addingTimeInterval(1.0))             // new lone tap
        XCTAssertTrue(d.registerTap(at: t.addingTimeInterval(1.2)))   // second pair
    }
}
