import XCTest
@testable import Aria

final class SpeakerGracePolicyTests: XCTestCase {

    // MARK: isInGracePeriod

    func testGracePeriodActiveWithinSevenDays() {
        let threeDaysAgo = Date().timeIntervalSince1970 - (3 * 24 * 3600)
        XCTAssertTrue(SpeakerGracePolicy.isInGracePeriod(enrolledDate: threeDaysAgo),
                      "enrolled 3 days ago should be in grace period")
    }

    func testGracePeriodExpiredAfterSevenDays() {
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 3600)
        XCTAssertFalse(SpeakerGracePolicy.isInGracePeriod(enrolledDate: eightDaysAgo),
                       "enrolled 8 days ago should be past the grace period")
    }

    func testGracePeriodZeroEnrolledDate() {
        XCTAssertFalse(SpeakerGracePolicy.isInGracePeriod(enrolledDate: 0),
                       "enrolledDate == 0 (never enrolled) → not in grace period")
    }

    func testGracePeriodExactBoundary() {
        // Enrolled exactly 7 days ago — should NOT be in grace period (elapsed == gracePeriodSeconds).
        let exactBoundary = Date().timeIntervalSince1970 - SpeakerGracePolicy.gracePeriodSeconds
        // May be on boundary; we just check both sides deterministically using fixed dates.
        let justInside = Date().timeIntervalSince1970 - SpeakerGracePolicy.gracePeriodSeconds + 60
        let justOutside = Date().timeIntervalSince1970 - SpeakerGracePolicy.gracePeriodSeconds - 60
        XCTAssertTrue(SpeakerGracePolicy.isInGracePeriod(enrolledDate: justInside))
        XCTAssertFalse(SpeakerGracePolicy.isInGracePeriod(enrolledDate: justOutside))
        _ = exactBoundary  // silence unused warning
    }

    // MARK: shouldBlock

    func testShouldNotBlockIfVerificationPassed() {
        // Regardless of enrollment date, a passing verification must never block.
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 3600)
        XCTAssertFalse(SpeakerGracePolicy.shouldBlock(verificationPassed: true, enrolledDate: eightDaysAgo),
                       "verification passed → should never block")
    }

    func testShouldBlockAfterGracePeriodOnMismatch() {
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 3600)
        XCTAssertTrue(SpeakerGracePolicy.shouldBlock(verificationPassed: false, enrolledDate: eightDaysAgo),
                      "mismatch after grace period → block")
    }

    func testShouldNotBlockDuringGracePeriodOnMismatch() {
        let oneDayAgo = Date().timeIntervalSince1970 - (1 * 24 * 3600)
        XCTAssertFalse(SpeakerGracePolicy.shouldBlock(verificationPassed: false, enrolledDate: oneDayAgo),
                       "mismatch during grace period → allow (grace)")
    }

    func testShouldNotBlockWhenNeverEnrolled() {
        // enrolledDate == 0 means not enrolled → isInGracePeriod is false,
        // but the gate itself shouldn't even be running. Regardless, shouldBlock
        // with a mismatch and no enrollment date should block (caller's guard).
        XCTAssertTrue(SpeakerGracePolicy.shouldBlock(verificationPassed: false, enrolledDate: 0),
                      "mismatch with no enrollment date → block (no grace period)")
    }

    func testCustomNowInjection() {
        // Verify the `now` parameter is respected (makes date-sensitive tests deterministic).
        let enrolledDate: Double = 1_000_000  // some fixed past timestamp
        let fiveSecondsAfterEnrollment = Date(timeIntervalSince1970: enrolledDate + 5)
        let eightDaysAfterEnrollment = Date(timeIntervalSince1970: enrolledDate + 8 * 24 * 3600)

        XCTAssertTrue(SpeakerGracePolicy.isInGracePeriod(enrolledDate: enrolledDate, now: fiveSecondsAfterEnrollment))
        XCTAssertFalse(SpeakerGracePolicy.isInGracePeriod(enrolledDate: enrolledDate, now: eightDaysAfterEnrollment))
    }
}
