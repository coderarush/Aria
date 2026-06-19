import Foundation

/// A bundle of execution policies (spec §93). Distinct from the Part 1
/// retry-focused `ExecutionPolicy`.
struct ExecutionPolicySet: Sendable {
    var interruptibility: Double
    var quality: Double
    var timeBudget: TimeInterval
    var costBudget: Double
    var verificationDepth: Int
    var failureTolerance: Double
}

/// Resolves the effective policy at each scope (spec §93): objective overrides
/// project, which overrides global.
actor ExecutionPolicyEngine {

    private var global: ExecutionPolicySet
    private var perProject: [UUID: ExecutionPolicySet] = [:]
    private var perObjective: [UUID: ExecutionPolicySet] = [:]

    init(global: ExecutionPolicySet) {
        self.global = global
    }

    func setGlobal(_ policy: ExecutionPolicySet) { global = policy }
    func setProject(_ policy: ExecutionPolicySet, for id: UUID) { perProject[id] = policy }
    func setObjective(_ policy: ExecutionPolicySet, for id: UUID) { perObjective[id] = policy }

    func effective(objectiveID: UUID?, projectID: UUID?) -> ExecutionPolicySet {
        if let objectiveID, let policy = perObjective[objectiveID] { return policy }
        if let projectID, let policy = perProject[projectID] { return policy }
        return global
    }
}
