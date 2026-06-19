import Foundation

/// Structured understanding of a visual scene (spec §74). No frames retained.
struct VisualUnderstanding: Sendable {
    let objects: [String]
    let changed: Bool
    let sceneSummary: String
    let confidence: Double
}

/// Summarizes a scene from already-extracted object lists and detects change
/// versus the previous frame — no recording, no surveillance (spec §74). Stores
/// observations only.
actor VisualContextEngine {

    private let perception: PerceptionEngine
    private var lastObjects: [String] = []

    init(perception: PerceptionEngine) {
        self.perception = perception
    }

    @discardableResult
    func observe(objects: [String]) async -> VisualUnderstanding {
        let changed = objects != lastObjects
        lastObjects = objects
        let summary = objects.joined(separator: ", ")
        let understanding = VisualUnderstanding(objects: objects, changed: changed,
                                                sceneSummary: summary, confidence: 0.7)

        await perception.ingest(Observation(
            source: "visual",
            confidence: understanding.confidence,
            payload: ["objects": summary, "changed": String(changed)],
            tags: ["visual"]))

        return understanding
    }
}
