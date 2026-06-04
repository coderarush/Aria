import Foundation

/// A durable fact Aria remembers about the user across sessions.
struct MemoryFact: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var kind: String        // "preference" | "fact" | "event"
    var createdAt: Date

    init(text: String, kind: String = "fact", id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.text = text; self.kind = kind; self.createdAt = createdAt
    }
}

/// Cross-session long-term memory: durable facts/preferences about the user,
/// persisted to `Application Support/Aria/memory.json`, recalled by relevance so Aria
/// feels like it KNOWS you instead of resetting every session.
actor LongTermMemory {
    /// Shared instance so the orchestrator (writes/recall) and Settings (view/forget)
    /// see the same in-memory state.
    static let shared = LongTermMemory()

    private(set) var facts: [MemoryFact] = []
    private let maxFacts = 500
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.facts = Self.load(from: self.fileURL)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aria", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("memory.json")
    }

    /// Remember a fact; ignores near-duplicates (same normalized text).
    @discardableResult
    func remember(_ text: String, kind: String = "fact") -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let norm = Self.normalize(trimmed)
        guard !facts.contains(where: { Self.normalize($0.text) == norm }) else { return false }
        facts.append(MemoryFact(text: trimmed, kind: kind))
        if facts.count > maxFacts { facts.removeFirst(facts.count - maxFacts) }
        save()
        return true
    }

    func all() -> [MemoryFact] { facts }

    func forget(id: UUID) {
        facts.removeAll { $0.id == id }
        save()
    }

    func clear() { facts = []; save() }

    /// Most relevant facts for a query (keyword overlap + recency), most-relevant first.
    func recall(for query: String, limit: Int = 5) -> [MemoryFact] {
        Self.rank(facts, query: query, now: Date()).prefix(limit).map { $0 }
    }

    // MARK: Ranking (pure — testable)

    static func rank(_ facts: [MemoryFact], query: String, now: Date) -> [MemoryFact] {
        let qTokens = tokens(query)
        return facts
            .compactMap { fact -> (MemoryFact, Double)? in
                let fTokens = tokens(fact.text)
                let overlap = Double(qTokens.intersection(fTokens).count)
                guard overlap > 0 else { return nil }   // require a real keyword match
                // Recency only tie-breaks among matches (newer slightly higher, ~30d decay).
                let ageDays = max(0, now.timeIntervalSince(fact.createdAt) / 86_400)
                let recency = max(0, 1.0 - ageDays / 30.0)
                return (fact, overlap * 2.0 + recency)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 })   // drop tiny stop-ish words
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [MemoryFact] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MemoryFact].self, from: data) else { return [] }
        return decoded
    }
}
