import XCTest
@testable import Aria

final class RegionWatchTests: XCTestCase {
    func testIdenticalIsNoChange() {
        XCTAssertFalse(RegionChange.changed(from: "Build: running", to: "Build: running"))
    }

    func testWhitespaceJitterIsNoChange() {
        XCTAssertFalse(RegionChange.changed(from: "Build:  running\n", to: "build: running"))
    }

    func testStatusFlipIsChange() {
        XCTAssertTrue(RegionChange.changed(from: "Build: running 42%", to: "Build: succeeded ✓"))
    }

    func testAppearOrDisappearIsChange() {
        XCTAssertTrue(RegionChange.changed(from: "", to: "Done"))
        XCTAssertTrue(RegionChange.changed(from: "Loading", to: ""))
    }

    func testSmallEditStaysUnderThreshold() {
        // One token of many changing should not trip a notification.
        let a = "the quarterly revenue report is nearly ready for review today"
        let b = "the quarterly revenue report is nearly ready for review now"
        XCTAssertFalse(RegionChange.changed(from: a, to: b))
    }

    func testIntentMatchesExplicitPhrasesOnly() {
        XCTAssertTrue(RegionWatchIntent.matches("watch this"))
        XCTAssertTrue(RegionWatchIntent.matches("tell me when this changes"))
        XCTAssertFalse(RegionWatchIntent.matches("watch the keynote later"))
        XCTAssertFalse(RegionWatchIntent.matches("what is this"))
    }

    func testStopActivityIntent() {
        XCTAssertTrue(StopActivityIntent.matches("stop watching"))
        XCTAssertTrue(StopActivityIntent.matches("stop the walkthrough"))
        XCTAssertTrue(StopActivityIntent.matches("clear the screen"))
        XCTAssertFalse(StopActivityIntent.matches("stop"))            // generic dismiss, not this
        XCTAssertFalse(StopActivityIntent.matches("what should I watch"))
    }
}
