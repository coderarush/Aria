import XCTest
@testable import Aria

final class OperationalReadinessTests: XCTestCase {
    func testReadySnapshotSummarizesEveryCoreCapability() {
        let readiness = OperationalReadiness(
            computerUseEnabled: true,
            screenRecordingEnabled: true,
            microphone: .granted,
            speech: .granted,
            linkedAccountCount: 2)

        XCTAssertFalse(readiness.needsSettings)
        XCTAssertFalse(readiness.needsConnectors)
        XCTAssertEqual(readiness.rows.map(\.title), ["Computer control", "Voice", "Vision", "Accounts"])
        XCTAssertEqual(readiness.rows.map(\.value), ["Ready", "Ready", "Ready", "2 linked"])
        XCTAssertTrue(readiness.rows.allSatisfy { $0.tone == .positive })
    }

    func testMissingPermissionsAreActionableWhileVisionStaysOptional() {
        let readiness = OperationalReadiness(
            computerUseEnabled: false,
            screenRecordingEnabled: false,
            microphone: .undetermined,
            speech: .denied,
            linkedAccountCount: 0)

        XCTAssertTrue(readiness.needsSettings)
        XCTAssertTrue(readiness.needsConnectors)
        XCTAssertEqual(readiness.rows[0].value, "Access needed")
        XCTAssertEqual(readiness.rows[0].tone, .attention)
        XCTAssertEqual(readiness.rows[1].value, "Setup needed")
        XCTAssertEqual(readiness.rows[2].value, "Optional")
        XCTAssertEqual(readiness.rows[2].tone, .neutral)
        XCTAssertEqual(readiness.rows[3].value, "No accounts linked")
    }

    func testVoiceRowNamesTheSpecificDeniedCapability() {
        let micBlocked = OperationalReadiness(
            computerUseEnabled: true, screenRecordingEnabled: true,
            microphone: .denied, speech: .granted, linkedAccountCount: 1)
        let speechBlocked = OperationalReadiness(
            computerUseEnabled: true, screenRecordingEnabled: true,
            microphone: .granted, speech: .denied, linkedAccountCount: 1)

        XCTAssertEqual(micBlocked.rows[1].detail, "Enable microphone access in Settings")
        XCTAssertEqual(speechBlocked.rows[1].detail, "Enable speech recognition in Settings")
    }
}
