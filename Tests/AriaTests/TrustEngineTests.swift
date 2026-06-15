import XCTest
@testable import Aria

final class TrustEngineTests: XCTestCase {
    func testOnlyImportantIrreversiblePausesAutonomous() {
        // The engine gates a step iff its importance requires approval.
        XCTAssertFalse(AutonomyEngine.shouldPause(tool: "file_write", input: ["path": "~/a"], summary: "save"))
        XCTAssertTrue(AutonomyEngine.shouldPause(tool: "send_mail", input: [:], summary: "email boss"))
        XCTAssertFalse(AutonomyEngine.shouldPause(tool: "ui_read", input: [:], summary: "read screen"))
        XCTAssertTrue(AutonomyEngine.shouldPause(tool: "comet", input: [:], summary: "delete the old backups"))
    }
}
