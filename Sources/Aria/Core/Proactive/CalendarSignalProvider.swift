import Foundation

/// A minimal, testable view of a calendar event — just what the provider needs.
/// The live EventKit fetch (in `AriaController`) maps `EKEvent` into this.
struct UpcomingEvent: Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
}

/// Surfaces a time-critical suggestion shortly before each upcoming calendar
/// event. The `fetch` closure is injected so tests run without EventKit.
struct CalendarSignalProvider: SignalProvider {
    let source: SuggestionSource = .calendar
    /// How far ahead of an event to start offering (seconds). Default 5 min.
    let leadWindow: TimeInterval
    let fetch: @Sendable (Date) async -> [UpcomingEvent]

    init(leadWindow: TimeInterval = 300,
         fetch: @escaping @Sendable (Date) async -> [UpcomingEvent]) {
        self.leadWindow = leadWindow
        self.fetch = fetch
    }

    func candidates(now: Date) async -> [Suggestion] {
        let events = await fetch(now)
        return events.compactMap { event in
            let delta = event.start.timeIntervalSince(now)
            guard delta > 0, delta <= leadWindow else { return nil }
            let minutes = max(1, Int((delta / 60).rounded()))
            let unit = minutes == 1 ? "minute" : "minutes"
            return Suggestion(
                source: .calendar,
                spokenLine: "\(event.title) starts in \(minutes) \(unit).",
                action: .acknowledge,
                confidence: 0.9,
                urgency: .timeCritical,
                createdAt: now,
                expiry: event.start,
                dedupeKey: "calendar:\(event.id)")
        }
    }
}
