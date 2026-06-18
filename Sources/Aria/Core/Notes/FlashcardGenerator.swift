import Foundation

struct Flashcard: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var front: String
    var back: String
    var category: String  // "term" | "concept" | "fill-in"
}

enum FlashcardError: Error, Equatable {
    case parseFailure(raw: String)
    case noSourceAvailable
}

struct FlashcardGenerator: Sendable {
    func generate(
        from source: String,
        topic: String,
        synthesize: @Sendable (String) async throws -> String
    ) async throws -> [Flashcard] {
        let prompt = """
        Generate 10 study flashcards from this content. Mix: term→definition, concept→explanation, fill-in-the-blank.
        Return ONLY a JSON array, no markdown:
        [{"front":"...","back":"...","category":"term|concept|fill-in"},...]

        Content:
        \(source)
        """
        let raw = try await synthesize(prompt)

        // Extract first [ to last ]
        guard let startIdx = raw.firstIndex(of: "["),
              let endIdx = raw.lastIndex(of: "]"), startIdx <= endIdx else {
            throw FlashcardError.parseFailure(raw: raw)
        }
        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else {
            throw FlashcardError.parseFailure(raw: raw)
        }

        var cards: [Flashcard] = []
        for item in array {
            guard let front = item["front"] as? String,
                  let back = item["back"] as? String,
                  let category = item["category"] as? String else { continue }
            cards.append(Flashcard(id: UUID(), front: front, back: back, category: category))
        }

        if cards.isEmpty {
            throw FlashcardError.parseFailure(raw: raw)
        }
        return cards
    }

    func save(_ cards: [Flashcard], topic: String) throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria Notes/Flashcards")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cards)
        let filename = "\(topic)-flashcards.json"
        try data.write(to: dir.appendingPathComponent(filename), options: .atomic)
    }
}
