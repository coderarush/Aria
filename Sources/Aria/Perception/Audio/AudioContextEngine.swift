import Foundation

/// Structured understanding of audio (spec §73). No raw audio retained.
struct AudioUnderstanding: Sendable {
    let speaking: Bool
    let speakerCount: Int
    let transcriptSummary: String
    let confidence: Double
}

/// Understands audio from transcript/speaker hooks — never raw audio bytes
/// (spec §73). Emits an observation carrying a summary only.
actor AudioContextEngine {

    private let perception: PerceptionEngine

    init(perception: PerceptionEngine) {
        self.perception = perception
    }

    @discardableResult
    func observe(transcript: String, speakerCount: Int) async -> AudioUnderstanding {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = String(trimmed.prefix(120))
        let understanding = AudioUnderstanding(speaking: !trimmed.isEmpty,
                                               speakerCount: speakerCount,
                                               transcriptSummary: summary,
                                               confidence: trimmed.isEmpty ? 0.3 : 0.8)

        await perception.ingest(Observation(
            source: "audio",
            confidence: understanding.confidence,
            payload: ["speaking": String(understanding.speaking),
                      "speakers": String(speakerCount),
                      "summary": summary],
            tags: ["audio"]))

        return understanding
    }
}
