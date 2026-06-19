import Foundation

/// Structured understanding of the active screen (spec §72). No raw image.
struct ScreenUnderstanding: Sendable {
    let app: String
    let intent: String
    let entities: [String]
    let relevance: Double
    let confidence: Double
}

/// Understands active work from structured screen signals (app, window title,
/// extracted text) — never screenshots (spec §72). Emits an observation
/// carrying only the structured summary.
actor ScreenContextEngine {

    private let perception: PerceptionEngine

    init(perception: PerceptionEngine) {
        self.perception = perception
    }

    @discardableResult
    func observe(app: String, windowTitle: String, extractedText: String) async -> ScreenUnderstanding {
        let intent = Self.deriveIntent(app: app, title: windowTitle)
        let entities = extractedText
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
            .filter { $0.first?.isUppercase ?? false }
        let relevance = entities.isEmpty ? 0.4 : 0.7

        let understanding = ScreenUnderstanding(app: app, intent: intent, entities: entities,
                                                relevance: relevance, confidence: 0.8)

        await perception.ingest(Observation(
            source: "screen",
            confidence: understanding.confidence,
            payload: ["app": app, "intent": intent, "entities": entities.joined(separator: ",")],
            tags: ["screen", intent]))

        return understanding
    }

    private static func deriveIntent(app: String, title: String) -> String {
        let t = (app + " " + title).lowercased()
        if t.contains("mail") || t.contains("compose") || t.contains("draft") || t.contains("doc") { return "writing" }
        if t.contains("xcode") || t.contains("code") || t.contains("terminal") { return "coding" }
        if t.contains("calendar") { return "scheduling" }
        return "browsing"
    }
}
