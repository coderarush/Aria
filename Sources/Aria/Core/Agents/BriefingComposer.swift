import Foundation
import EventKit
import AppKit

/// The Daily Briefing (V10 P3 — a signature workflow): gathers today's
/// calendar, due reminders, yesterday's work journal, and recently-touched
/// knowledge documents, then has the model compose a short, personal,
/// actionable briefing. Triggered on demand ("brief me") or by the scheduled
/// background agent (goal sentinel `aria.briefing`).
enum BriefingComposer {

    /// Background-agent goal sentinel — the coordinator routes this straight
    /// here instead of the open-ended autonomy planner (deterministic inputs,
    /// crafted output, no plan roulette).
    static let agentSentinel = "aria.briefing"

    static func isBriefingIntent(_ command: String) -> Bool {
        let c = command.lowercased()
        if c.contains("briefing") && !c.contains("briefcase") { return true }
        return c.contains("brief me")
    }

    /// The composition prompt — pure and testable. Empty sections read "(none)"
    /// so the model never invents content for missing inputs. V11 P4 adds
    /// active projects and recent notes (defaulted so existing callers/tests
    /// stay valid).
    static func prompt(calendar: String, reminders: String, yesterdayWork: String,
                       recentDocs: String, projects: String = "", notes: String = "",
                       date: Date) -> String {
        func section(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(none)" : s
        }
        let day = date.formatted(date: .complete, time: .omitted)
        return """
        Compose the user's daily briefing for \(day).

        Style: calm, personal, premium — like a great chief of staff. Three short
        sections with these exact headers: "Today", "Carry-over", "Suggested focus".
        Under Today: the schedule and due reminders, with times. Under Carry-over:
        what yesterday's work implies for today (done things need no action) and
        which active project most needs attention. Under Suggested focus: ONE
        concrete suggestion. Plain text, no markdown symbols, under 160 words
        total. Never invent events, work, projects, or notes.

        TODAY'S CALENDAR:
        \(section(calendar))

        REMINDERS DUE:
        \(section(reminders))

        YESTERDAY'S WORK (from Aria's journal):
        \(section(yesterdayWork))

        ACTIVE PROJECTS (most recently touched first):
        \(section(projects))

        RECENT NOTES:
        \(section(notes))

        RECENTLY TOUCHED DOCUMENTS:
        \(section(recentDocs))
        """
    }

    /// Gather inputs and compose. Returns (briefing text, ok). Runs the model
    /// through the normal generateText path (local-eligible class).
    static func compose(gemini: GeminiClient, now: Date = Date()) async -> (String, Bool) {
        let calendarLines = await calendarToday(now: now)
        let reminderLines = await remindersDue(now: now)
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        let startYesterday = cal.date(byAdding: .day, value: -1, to: startToday) ?? startToday
        let work = await WorkJournal.shared.digest(from: startYesterday, to: now)
        let docs = await KnowledgeIndex.shared.recentDocuments(limit: 5)
            .map(\.title).joined(separator: ", ")
        let projects = await activeProjects()
        let notes = await recentNoteTitles()

        let p = prompt(calendar: calendarLines, reminders: reminderLines,
                       yesterdayWork: work, recentDocs: docs,
                       projects: projects, notes: notes, date: now)
        do {
            let text = try await gemini.generateText(prompt: p, temperature: 0.4,
                                                     taskClass: .documentUnderstanding)
            return (text, true)
        } catch {
            // Model unreachable — deliver the raw inputs rather than nothing.
            var fallback = "Today:\n\(calendarLines.isEmpty ? "Nothing scheduled." : calendarLines)"
            if !reminderLines.isEmpty { fallback += "\nDue: \(reminderLines)" }
            if !work.isEmpty { fallback += "\nYesterday:\n\(work)" }
            return (fallback, false)
        }
    }

    /// Each active project with its latest outcome — "Verdai: ✓ deck — 6 slides".
    static func activeProjects(journal: WorkJournal = .shared) async -> String {
        let names = await journal.projects(limit: 3)
        var lines: [String] = []
        for name in names {
            let last = await journal.entries(project: name, limit: 1).first
            let tail = last.map { " — last: \($0.ok ? "✓" : "✗") \($0.title)" } ?? ""
            lines.append("• \(name)\(tail)")
        }
        return lines.joined(separator: "\n")
    }

    /// Recent Apple Notes titles — but only when Notes is already running and
    /// Automation access is in place. A scheduled briefing must never launch
    /// Notes or trigger a permission prompt; missing notes just read "(none)".
    private static func recentNoteTitles() async -> String {
        let notesRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .contains { $0.bundleIdentifier == "com.apple.Notes" }
        }
        guard notesRunning else { return "" }
        guard let result = try? await NotesReadTool().run(input: [:]), result.success,
              result.output.hasPrefix("Recent notes:") else { return "" }
        return String(result.output.dropFirst("Recent notes:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: inputs (EventKit reads only when access is already granted)

    private static func calendarToday(now: Date) async -> String {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return "" }
        let store = EKEventStore()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)
            .map { "• \($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "(untitled)")" }
            .joined(separator: "\n")
    }

    private static func remindersDue(now: Date) async -> String {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return "" }
        let store = EKEventStore()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let reminders = await withCheckedContinuation { (cont: CheckedContinuation<[EKReminder], Never>) in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        return reminders.prefix(8).map { "• \($0.title ?? "(untitled)")" }.joined(separator: "\n")
    }
}
