import Foundation

/// The reconstructed picture of recent work (spec §81).
struct RecallBundle: Sendable {
    let objective: String?
    let summary: String
    let recentActions: [String]
    let artifacts: [String]
}

/// Answers "what were we doing" / "continue" (spec §81) by reconstructing
/// context from the latest checkpoint and the memories tied to that objective.
actor RecallEngine {

    private let continuity: ContinuityEngine
    private let memory: MemoryEngine

    init(continuity: ContinuityEngine, memory: MemoryEngine) {
        self.continuity = continuity
        self.memory = memory
    }

    func recall() async -> RecallBundle {
        guard let checkpoint = await continuity.resumeLatest() else {
            return RecallBundle(objective: nil, summary: "nothing in progress",
                                recentActions: [], artifacts: [])
        }
        let related = await memory.all().filter { $0.objectiveID == checkpoint.objectiveID }
        let summary = related.map(\.summary).joined(separator: "; ")
        return RecallBundle(
            objective: checkpoint.objectiveID?.uuidString,
            summary: summary.isEmpty ? "in progress" : summary,
            recentActions: checkpoint.tools,
            artifacts: [])
    }
}
