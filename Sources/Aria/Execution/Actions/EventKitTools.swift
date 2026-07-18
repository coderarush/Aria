import Foundation
import EventKit

/// Parses the dates the model passes to the calendar/reminders tools. Prefers
/// ISO-8601 (the model is told the current time, so it can format absolute dates),
/// with a couple of forgiving fallbacks.
enum EventDates {
    static func parse(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // "yyyy-MM-dd HH:mm" / "yyyy-MM-dd"
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}

/// Add or list Calendar events via EventKit (a real API, not fragile AppleScript).
struct CalendarTool: AriaTool {
    static let name = "calendar"
    static let description = "Add or list Calendar events. Input: {action: add|list, title?, start? (ISO-8601), end? (ISO-8601), notes?, days? (look-ahead for list, default 7)}."
    static let paramHints: [String: String] = [
        "action": "add or list",
        "title": "Event title (for add)",
        "start": "Start time, ISO-8601 (for add)",
        "end": "End time, ISO-8601 (optional; defaults to 1h after start)",
        "days": "How many days ahead to list (for list)"
    ]

    static var hasUsageString: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard Self.hasUsageString else {
            return .fail("Calendar isn't available in this build — use the installed Aria app.")
        }
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            return .fail("Calendar access denied. Enable it in System Settings → Privacy & Security → Calendars.")
        }

        switch input["action"] ?? "list" {
        case "add":
            guard let title = input["title"], !title.isEmpty else { return .fail("Need an event title.") }
            guard let start = EventDates.parse(input["start"]) else { return .fail("Need a valid ISO-8601 start time.") }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = EventDates.parse(input["end"]) ?? start.addingTimeInterval(3600)
            event.notes = input["notes"]
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
                let when = event.startDate.formatted(date: .abbreviated, time: .shortened)
                return .ok("Added “\(title)” to your calendar for \(when).")
            } catch { return .fail("Couldn't save the event: \(error.localizedDescription)") }

        default: // list
            let days = Int(input["days"] ?? "7") ?? 7
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: max(1, days), to: start) ?? start
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            guard !events.isEmpty else { return .ok("Nothing on your calendar for the next \(days) days.") }
            let lines = events.prefix(15).map { e in
                "• \(e.startDate.formatted(date: .abbreviated, time: .shortened)) — \(e.title ?? "(untitled)")"
            }.joined(separator: "\n")
            return .ok("Upcoming events:\n\(lines)")
        }
    }
}

/// Add or list Reminders via EventKit.
struct RemindersTool: AriaTool {
    static let name = "reminders"
    static let description = "Add or list Reminders. Input: {action: add|list, title?, due? (ISO-8601, optional)}."
    static let paramHints: [String: String] = [
        "action": "add or list",
        "title": "Reminder text (for add)",
        "due": "Due time, ISO-8601 (optional, for add)"
    ]

    static var hasUsageString: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard Self.hasUsageString else {
            return .fail("Reminders isn't available in this build — use the installed Aria app.")
        }
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else {
            return .fail("Reminders access denied. Enable it in System Settings → Privacy & Security → Reminders.")
        }

        switch input["action"] ?? "list" {
        case "add":
            guard let title = input["title"], !title.isEmpty else { return .fail("Need a reminder.") }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = store.defaultCalendarForNewReminders()
            if let due = EventDates.parse(input["due"]) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: due)
            }
            do {
                try store.save(reminder, commit: true)
                return .ok("Added a reminder: “\(title)”.")
            } catch { return .fail("Couldn't save the reminder: \(error.localizedDescription)") }

        default: // list
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            let reminders = await withCheckedContinuation { (cont: CheckedContinuation<[EKReminder], Never>) in
                store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
            }
            guard !reminders.isEmpty else { return .ok("You have no open reminders.") }
            let lines = reminders.prefix(15).map { "• \($0.title ?? "(untitled)")" }.joined(separator: "\n")
            return .ok("Your reminders:\n\(lines)")
        }
    }
}
