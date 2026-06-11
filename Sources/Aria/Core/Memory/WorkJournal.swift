import Foundation

/// One unit of completed work Aria can recall later.
struct WorkEntry: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case task       // a voice/typed autonomy task
        case agent      // a background agent run
    }
    let date: Date
    let kind: Kind
    let title: String      // the goal/agent name, as the user phrased it
    let outcome: String    // one-line result summary
    let ok: Bool
}

/// Project memory (V10 P4): a durable journal of what Aria actually did —
/// tasks she ran, agents that fired, and how they ended — so "what were we
/// working on yesterday?" and "continue my Aria work" have a real answer.
/// Complements (never replaces) LongTermMemory facts and conversation memory.
actor WorkJournal {
    static let shared = WorkJournal()

    private let fileURL: URL
    private let cap: Int
    private var entries: [WorkEntry]

    init(fileURL: URL? = nil, cap: Int = 300) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("journal.json")
        self.fileURL = url
        self.cap = cap
        self.entries = Self.load(from: url)
    }

    func record(kind: WorkEntry.Kind, title: String, outcome: String, ok: Bool,
                at date: Date = Date()) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        entries.append(WorkEntry(date: date, kind: kind, title: trimmedTitle,
                                 outcome: String(outcome.prefix(200)), ok: ok))
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        save()
    }

    /// Chronological entries in [from, to).
    func entries(from: Date, to: Date) -> [WorkEntry] {
        entries.filter { $0.date >= from && $0.date < to }
    }

    /// Newest-first recent entries (the unified workflow-history view).
    func recent(_ limit: Int) -> [WorkEntry] {
        Array(entries.suffix(limit).reversed())
    }

    /// Newest-first free-text search over titles and outcomes.
    func search(_ query: String, limit: Int = 8) -> [WorkEntry] {
        let q = query.lowercased()
        return entries.reversed().filter {
            $0.title.lowercased().contains(q) || $0.outcome.lowercased().contains(q)
        }.prefix(limit).map { $0 }
    }

    /// Human-readable digest of a window — feeds the daily briefing and the
    /// recall tool's "yesterday/today" answers.
    func digest(from: Date, to: Date) -> String {
        let window = entries(from: from, to: to)
        guard !window.isEmpty else { return "" }
        return window.map { e in
            let time = e.date.formatted(date: .omitted, time: .shortened)
            let mark = e.ok ? "✓" : "✗"
            let tail = e.outcome.isEmpty ? "" : " — \(e.outcome)"
            return "\(mark) \(time) \(e.title)\(tail)"
        }.joined(separator: "\n")
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [WorkEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([WorkEntry].self, from: data)) ?? []
    }
}
