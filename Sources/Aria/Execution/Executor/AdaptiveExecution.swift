import Foundation

/// How carefully/aggressively to execute (spec §91).
enum ExecutionProfile: String, Sendable { case careful, balanced, fast, deep }

/// Adjusts execution *behavior* (never permissions, spec §91) from trust,
/// attention, and recent success. Default is balanced.
struct AdaptiveExecution: Sendable {

    func profile(trust: Double, attention: ActivityMode, recentSuccess: Double) -> ExecutionProfile {
        if trust < 0.4 { return .careful }
        if attention == .flow { return .deep }
        if trust >= 0.8 && recentSuccess >= 0.8 { return .fast }
        return .balanced
    }
}
