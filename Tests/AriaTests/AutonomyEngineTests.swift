import XCTest
@testable import Aria

final class AutonomyEngineTests: XCTestCase {
    func testRecognizesSaveIntent() {
        XCTAssertTrue(AutonomyEngine.isSaveIntent("Save the summary to a note"))
        XCTAssertTrue(AutonomyEngine.isSaveIntent("write it down for me"))
        XCTAssertTrue(AutonomyEngine.isSaveIntent("jot this in Notes"))
        XCTAssertFalse(AutonomyEngine.isSaveIntent("Research the best USB mics"))
        XCTAssertFalse(AutonomyEngine.isSaveIntent("open Spotify"))
    }

    func testTitleFromGoalIsCappedAndCapitalized() {
        let title = AutonomyEngine.titleFromGoal("research the best usb mics and save a summary to a note")
        XCTAssertTrue(title.hasPrefix("R"))                 // capitalized
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, 8)
        XCTAssertFalse(title.isEmpty)
    }
}
