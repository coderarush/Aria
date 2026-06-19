import Foundation

/// A captured resumption point (spec §32): everything needed to pick work back
/// up — the objective, the context, the tools in play, produced outputs, and
/// the runtime state at capture time.
struct Checkpoint: Identifiable, Sendable {

    enum Kind: String, Sendable { case manual, automatic, milestone, recovery }

    let id: UUID
    let timestamp: Date
    var kind: Kind
    var objectiveID: UUID?
    var context: [String: String]
    var tools: [String]
    var outputs: [UUID]
    var state: String

    init(id: UUID = UUID(),
         kind: Kind = .manual,
         objectiveID: UUID? = nil,
         context: [String: String] = [:],
         tools: [String] = [],
         outputs: [UUID] = [],
         state: String = RuntimeState.idle.rawValue,
         timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.objectiveID = objectiveID
        self.context = context
        self.tools = tools
        self.outputs = outputs
        self.state = state
        self.timestamp = timestamp
    }
}

/// Stores checkpoints in capture order (spec §32 CheckpointManager).
actor CheckpointManager {

    private var checkpoints: [Checkpoint] = []

    func capture(_ checkpoint: Checkpoint) {
        checkpoints.append(checkpoint)
    }

    func get(_ id: UUID) -> Checkpoint? { checkpoints.first { $0.id == id } }

    func latest() -> Checkpoint? { checkpoints.last }

    func latest(forObjective objectiveID: UUID) -> Checkpoint? {
        checkpoints.last { $0.objectiveID == objectiveID }
    }

    var all: [Checkpoint] { checkpoints }
}
