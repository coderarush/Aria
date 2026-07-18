import XCTest
@testable import Aria

final class Part6TrustFailureTests: XCTestCase {

    // MARK: - TrustDashboard (§115)

    func testSnapshotReflectsInputsAndExplains() {
        let dashboard = TrustDashboard()
        let score = ExecutionScore(successRate: 0.9, verificationRate: 0.8,
                                   correctionRate: 0.1, retryRate: 0.0)
        let snapshot = dashboard.snapshot(quality: score, authority: .execute,
                                          memoryCount: 12, permissionCount: 3, recoverable: true)
        XCTAssertEqual(snapshot.completionRate, 0.9, accuracy: 1e-9)
        XCTAssertEqual(snapshot.authority, .execute)
        XCTAssertEqual(snapshot.permissionCount, 3)

        let explanation = dashboard.explanation(for: snapshot)
        XCTAssertFalse(explanation.isEmpty)
        XCTAssertTrue(explanation.contains("execute"))   // why Aria could act
    }

    // MARK: - FailureExperience (§116)

    func testFailureExplainsRecoversNeverBlames() {
        let failure = FailureExperience()
        let response = failure.handle(error: "network timeout", recoverable: true)
        XCTAssertTrue(response.explanation.contains("network timeout"))
        XCTAssertTrue(response.recoverable)
        XCTAssertFalse(response.nextStep.isEmpty)   // never restart silently
        XCTAssertFalse(response.blamesUser)
    }

    func testNonRecoverableStillOffersNextStep() {
        let response = FailureExperience().handle(error: "permission denied", recoverable: false)
        XCTAssertFalse(response.recoverable)
        XCTAssertFalse(response.nextStep.isEmpty)
        XCTAssertFalse(response.blamesUser)
    }
}
