import Foundation

/// How much Aria is allowed to do on its own (spec §44).
///
/// The default is `.suggest`: Aria observes and proposes, but does not act
/// without approval. Execution requires `.execute` or higher.
enum AutonomyLevel: Int, Sendable, Comparable, CaseIterable {
    case observe = 0
    case suggest = 1
    case prepare = 2
    case execute = 3
    case autonomous = 4

    static func < (lhs: AutonomyLevel, rhs: AutonomyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether this level permits running actions without further approval.
    var allowsExecution: Bool { self >= .execute }

    static let `default`: AutonomyLevel = .suggest
}
