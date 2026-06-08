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

    // A user-declined confirmation must be distinguishable so the autonomy loop
    // does not retry/recover it (which would re-prompt for the same action).
    func testDeclinedResultIsRecognizedAndDistinct() {
        XCTAssertTrue(ToolResult.cancelled().wasDeclined)
        XCTAssertEqual(ToolResult.cancelled().output, ToolResult.notApprovedMessage)
        XCTAssertFalse(ToolResult.cancelled().success)
    }

    func testNonDeclineFailuresAreStillRetryable() {
        XCTAssertFalse(ToolResult.fail("save_note failed: disk full").wasDeclined)
        XCTAssertFalse(ToolResult.fail("Missing input 'content' for file_write.").wasDeclined)
        XCTAssertFalse(ToolResult.ok("done").wasDeclined)   // success is never a decline
    }

    // A model-unreachable failure must read as a connectivity problem, not as
    // "I couldn't work out how to do that."
    func testTransportMessageDistinguishesNetworkFromOther() {
        let offline = AutonomyEngine.transportMessage(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(offline.lowercased().contains("internet connection"))

        let timeout = AutonomyEngine.transportMessage(for: URLError(.timedOut))
        XCTAssertTrue(timeout.lowercased().contains("internet connection"))

        // Non-URL (e.g. auth/quota) → key + connection guidance, not the generic plan miss.
        struct APIError: Error {}
        let other = AutonomyEngine.transportMessage(for: APIError())
        XCTAssertTrue(other.lowercased().contains("api key"))
        XCTAssertFalse(other.lowercased().contains("couldn't work out"))
    }

    // #5: a blind retry is skipped for declines and missing-input (won't change);
    // other failures stay retryable.
    func testNonRetryableFailureClassification() {
        XCTAssertTrue(ToolResult.cancelled().isNonRetryableFailure)
        XCTAssertTrue(ToolResult.fail("Missing input 'content' for file_write.").isNonRetryableFailure)
        XCTAssertFalse(ToolResult.fail("shell failed: exit 1").isNonRetryableFailure)
        XCTAssertFalse(ToolResult.ok("done").isNonRetryableFailure)
    }

    // #4: financial / system danger words must trip the gate via the unified list.
    func testSafetyCoversFinancialAndSystemActions() {
        XCTAssertTrue(Safety.isDestructive(summary: "pay the invoice"))
        XCTAssertTrue(Safety.isDestructive(summary: "purchase the upgrade"))
        XCTAssertTrue(Safety.isDestructive(summary: "format the disk"))
        XCTAssertTrue(Safety.isDestructive(summary: "submit the order form"))
        XCTAssertFalse(Safety.isDestructive(summary: "summarize the page"))
    }
}
