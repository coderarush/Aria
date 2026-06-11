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
    /// Project Memory 2.0 (V11 P5): which project this work belongs to.
    /// Optional so journals written before V11 decode unchanged.
    var project: String?
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

    init(fileURL: URL? = nil, cap: Int = 1000) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("journal.json")
        self.fileURL = url
        self.cap = cap
        self.entries = Self.load(from: url)
    }

    func record(kind: WorkEntry.Kind, title: String, outcome: String, ok: Bool,
                project: String? = nil, at date: Date = Date()) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let tag = project ?? ProjectTagger.infer(from: trimmedTitle)
        entries.append(WorkEntry(date: date, kind: kind, title: trimmedTitle,
                                 outcome: String(outcome.prefix(200)), ok: ok,
                                 project: tag))
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

    /// Newest-first entries tagged with `project` (case-insensitive).
    func entries(project: String, limit: Int = 20) -> [WorkEntry] {
        let p = project.lowercased()
        return entries.reversed().filter { $0.project?.lowercased() == p }
            .prefix(limit).map { $0 }
    }

    /// Distinct projects, most recently touched first.
    func projects(limit: Int = 12) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in entries.reversed() {
            guard let p = e.project, seen.insert(p.lowercased()).inserted else { continue }
            out.append(p)
            if out.count == limit { break }
        }
        return out
    }

    /// Human-readable digest of one project's recent work — feeds
    /// "continue my X work" with where things actually stand.
    func projectDigest(_ project: String, limit: Int = 10) -> String {
        entries(project: project, limit: limit).map { e in
            let day = e.date.formatted(date: .abbreviated, time: .shortened)
            let mark = e.ok ? "✓" : "✗"
            let tail = e.outcome.isEmpty ? "" : " — \(e.outcome)"
            return "\(mark) \(day) \(e.title)\(tail)"
        }.joined(separator: "\n")
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
