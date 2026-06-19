import Foundation

/// A transparent read of the trust state (spec §115).
struct TrustSnapshot: Sendable {
    let completionRate: Double
    let verificationRate: Double
    let authority: AutonomyLevel
    let memoryCount: Int
    let permissionCount: Int
    let recoverable: Bool
}

/// Shows the user why Aria could act (spec §115): completion, verification,
/// authority, memory usage, permissions, recoverability. Read-only.
struct TrustDashboard: Sendable {

    func snapshot(quality: ExecutionScore,
                  authority: AutonomyLevel,
                  memoryCount: Int,
                  permissionCount: Int,
                  recoverable: Bool) -> TrustSnapshot {
        TrustSnapshot(completionRate: quality.successRate,
                      verificationRate: quality.verificationRate,
                      authority: authority,
                      memoryCount: memoryCount,
                      permissionCount: permissionCount,
                      recoverable: recoverable)
    }

    /// A plain explanation of why Aria acted as it did.
    func explanation(for snapshot: TrustSnapshot) -> String {
        let pct = Int(snapshot.completionRate * 100)
        return "Acting at \(String(describing: snapshot.authority)) authority with \(snapshot.permissionCount) "
            + "granted permissions; \(pct)% completion, "
            + (snapshot.recoverable ? "recoverable." : "not recoverable.")
    }
}
