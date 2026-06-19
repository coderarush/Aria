import Foundation

/// Tracks how much confidence Aria has earned (spec §55).
///
/// The goal is confidence, not autonomy. Confidence blends the available
/// success rates (verification, tools, recovery) and is penalised by user
/// corrections. With no signal yet it sits neutral at 0.5.
actor TrustEngine {

    private var verificationPass = 0, verificationTotal = 0
    private var toolSuccess = 0, toolTotal = 0
    private var recoveryOK = 0, recoveryTotal = 0
    private var corrections = 0

    func recordVerification(passed: Bool) {
        verificationTotal += 1
        if passed { verificationPass += 1 }
    }

    func recordTool(success: Bool) {
        toolTotal += 1
        if success { toolSuccess += 1 }
    }

    func recordRecovery(succeeded: Bool) {
        recoveryTotal += 1
        if succeeded { recoveryOK += 1 }
    }

    func recordCorrection() { corrections += 1 }

    /// Current execution confidence in 0…1.
    func confidence() -> Double {
        var rates: [Double] = []
        if verificationTotal > 0 { rates.append(Double(verificationPass) / Double(verificationTotal)) }
        if toolTotal > 0 { rates.append(Double(toolSuccess) / Double(toolTotal)) }
        if recoveryTotal > 0 { rates.append(Double(recoveryOK) / Double(recoveryTotal)) }

        let base = rates.isEmpty ? 0.5 : rates.reduce(0, +) / Double(rates.count)
        let penalised = base - 0.1 * Double(corrections)
        return min(1.0, max(0.0, penalised))
    }
}
