import Foundation

/// Project memory recall — answers "what were we working on yesterday?",
/// "what did we do this week?", "find the task about X". Reads the work
/// journal (tasks Aria ran, background agent runs, outcomes).
struct RecallWorkTool: AriaTool {
    static let name = "recall_work"
    static let description = "Recall what the user and Aria worked on before. Input: {timeframe: today|yesterday|this week|last week} or {query: free text}. Use when the user asks about previous work, recent projects, what happened earlier, or wants to continue something."
    static let paramHints: [String: String] = [
        "timeframe": "today, yesterday, this week, or last week",
        "query": "Free-text search over past work instead of a timeframe"
    ]

    private let journal: WorkJournal
    private let now: () -> Date

    init(journal: WorkJournal = .shared, now: @escaping () -> Date = Date.init) {
        self.journal = journal
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        if let query = input["query"], !query.isEmpty {
            let hits = await journal.search(query)
            guard !hits.isEmpty else { return .ok("Nothing in the work journal matches “\(query)”.") }
            let lines = hits.map { e in
                "\(e.ok ? "✓" : "✗") \(e.date.formatted(date: .abbreviated, time: .shortened)) — \(e.title)\(e.outcome.isEmpty ? "" : " (\(e.outcome))")"
            }.joined(separator: "\n")
            return .ok("Past work matching “\(query)”:\n\(lines)")
        }

        let timeframe = (input["timeframe"] ?? "today").lowercased()
        guard let (from, to, label) = Self.window(for: timeframe, now: now()) else {
            return .fail("Unknown timeframe “\(timeframe)” — use today, yesterday, this week, or last week.")
        }
        let digest = await journal.digest(from: from, to: to)
        guard !digest.isEmpty else { return .ok("Nothing in the work journal for \(label).") }
        return .ok("Work \(label):\n\(digest)")
    }

    /// [from, to) window + spoken label for a timeframe keyword.
    static func window(for timeframe: String, now: Date = Date(),
                       calendar: Calendar = .current) -> (Date, Date, String)? {
        let startOfToday = calendar.startOfDay(for: now)
        switch timeframe {
        case "today":
            return (startOfToday, now, "today")
        case "yesterday":
            guard let y = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return nil }
            return (y, startOfToday, "yesterday")
        case "this week":
            guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
            return (start, now, "this week")
        case "last week":
            guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
                  let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) else { return nil }
            return (start, thisWeek, "last week")
        default:
            return nil
        }
    }
}
