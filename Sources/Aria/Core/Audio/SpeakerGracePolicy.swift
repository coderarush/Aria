import Foundation

/// Grace-period policy for the experimental speaker verification gate.
/// During the first 7 days after enrolling, voice mismatches warn rather than
/// block — giving the basic voiceprint time to prove itself before it can
/// lock the owner out. Pure functions (no state) so tests are synchronous.
enum SpeakerGracePolicy {
    static let gracePeriodSeconds: Double = 7 * 24 * 3600  // 7 days

    /// Returns true if currently in grace period (enrolled but < 7 days ago).
    /// enrolledDate == 0 (or negative) means never enrolled → not in grace period.
    static func isInGracePeriod(enrolledDate: Double, now: Date = Date()) -> Bool {
        guard enrolledDate > 0 else { return false }
        let elapsed = now.timeIntervalSince1970 - enrolledDate
        return elapsed < gracePeriodSeconds
    }

    /// During grace period: warn but don't block. After: block on mismatch.
    /// - Parameters:
    ///   - verificationPassed: Whether the voice matched the enrolled profile.
    ///   - enrolledDate: timeIntervalSince1970 when enrollment completed (0 = never).
    ///   - now: Current time (injectable for tests).
    /// - Returns: true when the command should be blocked.
    static func shouldBlock(verificationPassed: Bool, enrolledDate: Double, now: Date = Date()) -> Bool {
        if verificationPassed { return false }
        return !isInGracePeriod(enrolledDate: enrolledDate, now: now)
    }
}
