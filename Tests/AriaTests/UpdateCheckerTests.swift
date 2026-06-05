import XCTest
@testable import Aria

final class UpdateCheckerTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("v5.1.0", than: "5.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("6.0.0", than: "5.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("v5.0.1", than: "5.0.0"))
    }
    func testNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("v5.0.0", than: "5.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("4.9.0", than: "5.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v5.0.0", than: "5.0.1"))
    }
    func testToleratesMissingComponents() {
        XCTAssertTrue(UpdateChecker.isNewer("v6", than: "5.9"))
        XCTAssertFalse(UpdateChecker.isNewer("v5", than: "5.0.0"))
    }
}
