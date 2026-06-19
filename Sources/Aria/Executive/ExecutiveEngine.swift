import Foundation

/// Converts objectives into sustained progress (spec §89): understand →
/// prioritize → schedule → prepare → execute → verify → follow up → close.
///
/// Authority is earned, never assumed (spec §88): the executive only executes
/// when the delegation's authority permits it; otherwise it prepares and parks
/// the work for approval (spec §106 — never execute without authority).
actor ExecutiveEngine {

    private let delegation: DelegationEngine
    private let coordinator: Coordinator

    init(delegation: DelegationEngine, coordinator: Coordinator) {
        self.delegation = delegation
        self.coordinator = coordinator
    }

    func handle(objective: String,
                steps: [PlanStep],
                rules: [String],
                authority: AutonomyLevel) async -> DelegationContract {
        let contract = await delegation.delegate(
            objective: objective, constraints: [], authority: authority,
            deadline: nil, verification: rules, success: objective)
        await delegation.setState(contract.id, .accepted)

        guard authority.allowsExecution else {
            // Prepared, but not authorized to act — await approval.
            await delegation.setState(contract.id, .preparing)
            await delegation.setState(contract.id, .review)
            return await delegation.get(contract.id) ?? contract
        }

        await delegation.setState(contract.id, .executing)
        let domainObjective = Domain.Objective(title: objective, intent: objective)
        let result = await coordinator.run(objective: domainObjective, steps: steps, rules: rules)
        await delegation.setState(contract.id, result.status == .completed ? .completed : .blocked)
        return await delegation.get(contract.id) ?? contract
    }
}
