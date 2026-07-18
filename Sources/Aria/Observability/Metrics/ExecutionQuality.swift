import Foundation

/// A longitudinal execution-quality score (spec §110).
struct ExecutionScore: Sendable {
    let successRate: Double
    let verificationRate: Double
    let correctionRate: Double
    let retryRate: Double

    /// Weighted composite — rewards success/verification, penalises corrections
    /// and retries.
    var composite: Double {
        successRate * 0.4
            + verificationRate * 0.3
            + (1 - correctionRate) * 0.2
            + (1 - min(1, retryRate)) * 0.1
    }
}

/// Tracks execution quality over time (spec §110): time saved, success,
/// corrections, verification, retries.
actor ExecutionQuality {

    private var attempts = 0
    private var successes = 0
    private var verifications = 0
    private var corrections = 0
    private var retries = 0

    func record(success: Bool, verified: Bool, corrected: Bool, retries retryCount: Int) {
        attempts += 1
        if success { successes += 1 }
        if verified { verifications += 1 }
        if corrected { corrections += 1 }
        retries += retryCount
    }

    func score() -> ExecutionScore {
        guard attempts > 0 else { return ExecutionScore(successRate: 0, verificationRate: 0, correctionRate: 0, retryRate: 0) }
        let n = Double(attempts)
        return ExecutionScore(
            successRate: Double(successes) / n,
            verificationRate: Double(verifications) / n,
            correctionRate: Double(corrections) / n,
            retryRate: Double(retries) / n)
    }
}
