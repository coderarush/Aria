import Foundation

struct FlashcardGenerateTool: AriaTool {
    static let name = "flashcards_generate"
    static let description = "Generate study flashcards from lecture notes or provided text. Input: optional topic (string), optional source (raw text). If no source, uses most recent lecture note."
    static let paramHints: [String: String] = [
        "topic": "Topic label for the flashcard set (optional).",
        "source": "Raw text to generate flashcards from (optional; uses latest lecture note if omitted)."
    ]

    private let gemini: GeminiClient
    private let generator: FlashcardGenerator

    init(gemini: GeminiClient = GeminiClient(), generator: FlashcardGenerator = FlashcardGenerator()) {
        self.gemini = gemini
        self.generator = generator
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let topic = input["topic"] ?? "flashcards"
        let source: String

        if let providedSource = input["source"], !providedSource.isEmpty {
            source = providedSource
        } else {
            // Load most recent lecture note
            let lecturesDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Aria Notes/Lectures")
            guard let lectureURL = mostRecentJSON(in: lecturesDir) else {
                return .ok("No lecture notes found. Start a lecture first or provide source text.")
            }
            guard let data = try? Data(contentsOf: lectureURL),
                  let note = try? JSONDecoder().decode(LectureNote.self, from: data) else {
                return .ok("No lecture notes found. Start a lecture first or provide source text.")
            }
            source = note.rawTranscript
        }

        let cards: [Flashcard]
        do {
            cards = try await generator.generate(from: source, topic: topic) { [gemini] prompt in
                try await gemini.generateText(prompt: prompt, temperature: 0.4)
            }
        } catch let error as FlashcardError {
            switch error {
            case .parseFailure(let raw):
                return .fail("Failed to parse flashcards from model response: \(raw.prefix(200))")
            case .noSourceAvailable:
                return .fail("No source content available.")
            }
        }

        try? generator.save(cards, topic: topic)
        return .ok("Generated \(cards.count) flashcards for '\(topic)'.")
    }

    // MARK: - Helpers

    private func mostRecentJSON(in dir: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let jsonFiles = items.filter { $0.pathExtension == "json" }
        return jsonFiles.max(by: { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return aDate < bDate
        })
    }
}
