import Foundation

/// Persists conversation turns to `Application Support/Aria/conversation.json`.
/// Keeps the last 50 on disk; exposes the last 6 for Gemini context.
actor ConversationMemory {
    private(set) var turns: [ConversationTurn] = []

    private let maxStored = 50
    private let contextWindow = 6
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.turns = Self.loadTurns(from: url)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aria", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversation.json")
    }

    func append(_ turn: ConversationTurn) {
        turns.append(turn)
        if turns.count > maxStored {
            turns.removeFirst(turns.count - maxStored)
        }
        save()
    }

    /// The last N turns, oldest-first, for Gemini context.
    func recentContext() -> [ConversationTurn] {
        Array(turns.suffix(contextWindow))
    }

    /// Simple substring search for "what did I ask earlier?".
    func search(_ query: String) -> [ConversationTurn] {
        let q = query.lowercased()
        return turns.filter {
            $0.transcript.lowercased().contains(q)
            || $0.responseMessage.lowercased().contains(q)
        }
    }

    func clear() {
        turns = []
        save()
    }

    // MARK: Persistence

    private nonisolated static func loadTurns(from url: URL) -> [ConversationTurn] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConversationTurn].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(turns)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.memory.error("Failed to persist conversation: \(error.localizedDescription)")
        }
    }
}
