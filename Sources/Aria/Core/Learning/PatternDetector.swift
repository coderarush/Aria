import Foundation

/// Pure, deterministic pattern detection over observed commands. Kept separate
/// from PatternEngine so it can be unit-tested without I/O or time dependence.
enum PatternDetector {

    /// Rules from the spec.
    static let minOccurrences = 5
    static let minConsistency = 0.70
    static let windowMinutes = 30
    static let expiryDays = 30

    /// Detect recurring time-of-day command patterns.
    /// - sensitivity: minimum confidence to surface (0.6 aggressive … 0.9 conservative).
    static func detectTimePatterns(commands: [CommandEvent],
                                   sensitivity: Double,
                                   calendar: Calendar = .current) -> [BehaviorPattern] {
        let groups = Dictionary(grouping: commands) { normalize($0.command) }
        var patterns: [BehaviorPattern] = []

        for (command, events) in groups where events.count >= minOccurrences {
            let minutes = events.map { minuteOfDay($0.timestamp, calendar) }
            guard let center = circularMeanMinute(minutes) else { continue }

            let within = minutes.filter { angularDistance($0, center) <= windowMinutes }.count
            let consistency = Double(within) / Double(events.count)
            guard consistency >= minConsistency, consistency >= sensitivity else { continue }

            let days = Set(events.map { Weekday(date: $0.timestamp, calendar: calendar) })
            let pattern = BehaviorPattern(
                description: describe(command: command, minute: center, days: days),
                trigger: .timeOfDay(hour: center / 60, minute: center % 60, days: days),
                action: .runSavedCommand(command),
                confidence: consistency,
                occurrences: events.map(\.timestamp).sorted(),
                status: .observing)
            patterns.append(pattern)
        }
        return patterns.sorted { $0.confidence > $1.confidence }
    }

    /// A pattern has expired if its most recent occurrence is older than 30 days.
    static func isExpired(_ pattern: BehaviorPattern, now: Date = Date()) -> Bool {
        guard let last = pattern.occurrences.max() else { return true }
        return now.timeIntervalSince(last) > Double(expiryDays) * 24 * 3600
    }

    /// Does a time-of-day trigger match `now` within the ±window?
    static func triggerMatches(_ trigger: PatternTrigger,
                               now: Date,
                               calendar: Calendar = .current) -> Bool {
        switch trigger {
        case let .timeOfDay(hour, minute, days):
            let today = Weekday(date: now, calendar: calendar)
            guard days.isEmpty || days.contains(today) else { return false }
            let nowMin = minuteOfDay(now, calendar)
            return angularDistance(nowMin, hour * 60 + minute) <= windowMinutes
        case let .compound(triggers):
            return triggers.allSatisfy { triggerMatches($0, now: now, calendar: calendar) }
        case .appLaunched, .appQuit, .fileModified:
            return false  // event-driven, matched elsewhere
        }
    }

    // MARK: Helpers

    static func normalize(_ command: String) -> String {
        command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Distance on a 1440-minute circle (so 23:50 and 00:10 are 20 apart).
    static func angularDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % 1440
        return min(d, 1440 - d)
    }

    /// Circular mean of minute-of-day values (handles midnight wraparound).
    static func circularMeanMinute(_ minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        var sumSin = 0.0, sumCos = 0.0
        for m in minutes {
            let angle = Double(m) / 1440 * 2 * .pi
            sumSin += sin(angle); sumCos += cos(angle)
        }
        var angle = atan2(sumSin, sumCos)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded()) % 1440
    }

    static func describe(command: String, minute: Int, days: Set<Weekday>) -> String {
        let h = minute / 60, m = minute % 60
        let time = String(format: "%02d:%02d", h, m)
        let weekdayOnly = days == Set([.monday, .tuesday, .wednesday, .thursday, .friday])
        let when = days.count >= 7 ? "every day"
            : weekdayOnly ? "every weekday"
            : "on some days"
        return "You say \"\(command)\" \(when) around \(time)"
    }
}
