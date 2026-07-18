import Foundation

/// State for the operational execution view (spec §57): objective header,
/// action timeline, progress, artifacts, continue affordance. Aria looks
/// operational, not conversational — no message bubbles here, just work state.
struct ExecutionSurfaceState: Sendable {
    var objectiveTitle: String
    var actions: [String]
    var progress: Double
    var artifacts: [String]
    var canContinue: Bool

    init(objectiveTitle: String, actions: [String], progress: Double,
         artifacts: [String], canContinue: Bool) {
        self.objectiveTitle = objectiveTitle
        self.actions = actions
        self.progress = progress
        self.artifacts = artifacts
        self.canContinue = canContinue
    }

    /// Build the view state from a completed execution contract.
    init(from contract: ExecutionContract, title: String) {
        self.objectiveTitle = title
        self.actions = contract.actions.map(\.uuidString)
        self.progress = contract.status == .completed ? 1.0 : 0.0
        self.artifacts = contract.artifacts.map(\.reference)
        self.canContinue = contract.recoverable
    }
}
