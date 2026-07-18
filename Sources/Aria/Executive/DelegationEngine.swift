import Foundation

/// The terms of a delegated objective (spec §90).
struct DelegationContract: Identifiable, Sendable {
    enum State: String, Sendable {
        case requested, accepted, clarifying, preparing, waiting, executing, blocked, review, completed
    }

    let id: UUID
    var objective: String
    var constraints: [String]
    var authority: AutonomyLevel
    var deadline: Date?
    var verification: [String]
    var success: String
    var state: State
}

/// Accepts and tracks delegated work (spec §90): accept, clarify, plan, track
/// ownership, report, handoff. Authority is recorded, not assumed.
actor DelegationEngine {

    private var contracts: [UUID: DelegationContract] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    @discardableResult
    func delegate(objective: String,
                  constraints: [String],
                  authority: AutonomyLevel,
                  deadline: Date?,
                  verification: [String],
                  success: String) async -> DelegationContract {
        let contract = DelegationContract(id: UUID(), objective: objective, constraints: constraints,
                                          authority: authority, deadline: deadline,
                                          verification: verification, success: success, state: .requested)
        contracts[contract.id] = contract
        await eventBus.emit(AriaEvent(
            kind: .objectiveCreated,
            source: "DelegationEngine",
            payload: ["id": contract.id.uuidString, "objective": objective]))
        return contract
    }

    func get(_ id: UUID) -> DelegationContract? { contracts[id] }

    func setState(_ id: UUID, _ state: DelegationContract.State) {
        contracts[id]?.state = state
    }

    /// A one-line status report (spec §90 report).
    func report(_ id: UUID) -> String {
        guard let contract = contracts[id] else { return "unknown delegation" }
        return "\(contract.objective): \(contract.state.rawValue)"
    }
}
