import Foundation

/// One event on the Aria Timeline (V11 P6).
struct TimelineEvent: Equatable, Sendable {
    enum Source: String, Sendable {
        case task    // a voice/typed autonomy task (work journal)
        case agent   // a background agent run (work journal)
        case action  // an individual tool action (activity log)
    }
    let date: Date
    let source: Source
    let title: String
    let detail: String
    let ok: Bool
    let project: String?
}

/// The Aria Timeline: "what did I do today?", "show my week". A pure
/// aggregation view over the stores that already capture work — the work
/// journal (tasks + agent runs, with project tags) and the activity log
/// (individual tool actions). Owns no persistence of its own.
struct Timeline: Sendable {
    let journal: WorkJournal
    let activity: ActivityLog

    init(journal: WorkJournal = .shared, activity: ActivityLog = .shared) {
        self.journal = journal
        self.activity = activity
    }

    /// All events in [from, to), chronological.
    func events(from: Date, to: Date) async -> [TimelineEvent] {
        let work = await journal.entries(from: from, to: to).map { e in
            TimelineEvent(date: e.date,
                          source: e.kind == .task ? .task : .agent,
                          title: e.title, detail: e.outcome, ok: e.ok,
                          project: e.project)
        }
        let actions = await activity.entries(from: from, to: to).map { a in
            TimelineEvent(date: a.date, source: .action,
                          title: a.detail.isEmpty ? a.tool : a.detail,
                          detail: a.summary, ok: a.outcome == .ok,
                          project: nil)
        }
        return (work + actions).sorted { $0.date < $1.date }
    }

    /// Multi-day digest grouped by day with completion counts — "show my week".
    /// Caps listed items per day so a busy week stays speakable.
    func dayRollup(from: Date, to: Date, itemsPerDay: Int = 5,
                   calendar: Calendar = .current) async -> String {
        let all = await events(from: from, to: to)
        guard !all.isEmpty else { return "" }
        let byDay = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted().map { dayStart in
            let dayEvents = byDay[dayStart] ?? []
            let done = dayEvents.filter(\.ok).count
            let failed = dayEvents.count - done
            let header = dayStart.formatted(.dateTime.month(.abbreviated).day())
                + " — \(done) done" + (failed > 0 ? ", \(failed) failed" : "")
            let lines = dayEvents.prefix(itemsPerDay).map { e in
                "  \(e.ok ? "✓" : "✗") \(e.title)\(e.project.map { " [\($0)]" } ?? "")"
            }
            let more = dayEvents.count > itemsPerDay
                ? ["  … and \(dayEvents.count - itemsPerDay) more"] : []
            return ([header] + lines + more).joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
