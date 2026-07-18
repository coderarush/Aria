import Foundation

/// How far initiative may go (spec §98). The ladder tops out at awaitApproval —
/// initiative NEVER executes (spec §98/§106).
enum InitiativeLevel: Int, Sendable, Comparable, CaseIterable {
    case notice, suggest, prepare, recommend, awaitApproval
    static func < (lhs: InitiativeLevel, rhs: InitiativeLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What prompted an initiative (spec §98).
enum InitiativeTrigger: String, Sendable { case deadline, contextShift, unfinished, repetition }

/// A raised initiative.
struct Initiative: Identifiable, Sendable {
    let id: UUID
    let trigger: InitiativeTrigger
    let level: InitiativeLevel
    let summary: String
}

/// Controlled proactivity (spec §98). Raises initiatives capped at a policy
/// maximum; the absolute ceiling is awaitApproval, so initiative can never
/// execute without explicit authority.
actor InitiativeEngine {

    private let maxLevel: InitiativeLevel
    private var initiatives: [Initiative] = []

    init(maxLevel: InitiativeLevel = .awaitApproval) {
        self.maxLevel = maxLevel
    }

    @discardableResult
    func raise(trigger: InitiativeTrigger, summary: String, suggestedLevel: InitiativeLevel) -> Initiative {
        let level = min(suggestedLevel, maxLevel)
        let initiative = Initiative(id: UUID(), trigger: trigger, level: level, summary: summary)
        initiatives.append(initiative)
        return initiative
    }

    func pending() -> [Initiative] { initiatives }
}
