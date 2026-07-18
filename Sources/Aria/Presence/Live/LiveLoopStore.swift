import Foundation

/// Durable Live Loop bookkeeping: per-recognizer cooldowns, snooze/never, and
/// the "did today's brief already run" day stamp. UserDefaults-backed so a
/// relaunch can't replay this morning's brief or re-offer a snoozed card.
/// `@unchecked` because UserDefaults is documented thread-safe.
struct LiveLoopStore: @unchecked Sendable {

    /// Minimum gap between two fires of the same playbook.
    static let cooldowns: [String: TimeInterval] = [
        PlaybookLibrary.meetingPrep: 20 * 60,
        PlaybookLibrary.inboxTriage: 60 * 60,
        PlaybookLibrary.screenCoPilot: 90 * 60,
        PlaybookLibrary.dailyBrief: 4 * 60 * 60,
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static func lastFired(_ id: String) -> String { "liveloop.lastFired.\(id)" }
        static func snoozedUntil(_ id: String) -> String { "liveloop.snoozedUntil.\(id)" }
        static let never = "liveloop.never"
        static let briefDay = "liveloop.lastBriefDay"
    }

    // MARK: Cooldown

    func markFired(_ playbookID: String, now: Date) {
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastFired(playbookID))
    }

    func isCoolingDown(_ playbookID: String, now: Date) -> Bool {
        let last = defaults.double(forKey: Key.lastFired(playbookID))
        guard last > 0 else { return false }
        let gap = Self.cooldowns[playbookID] ?? 30 * 60
        return now.timeIntervalSince1970 - last < gap
    }

    // MARK: Snooze / never

    func snooze(_ playbookID: String, until: Date) {
        defaults.set(until.timeIntervalSince1970, forKey: Key.snoozedUntil(playbookID))
    }

    func isSnoozed(_ playbookID: String, now: Date) -> Bool {
        now.timeIntervalSince1970 < defaults.double(forKey: Key.snoozedUntil(playbookID))
    }

    func setNever(_ playbookID: String) {
        var set = Set(defaults.stringArray(forKey: Key.never) ?? [])
        set.insert(playbookID)
        defaults.set(Array(set), forKey: Key.never)
    }

    func isNever(_ playbookID: String) -> Bool {
        (defaults.stringArray(forKey: Key.never) ?? []).contains(playbookID)
    }

    func clearNever(_ playbookID: String) {
        var set = Set(defaults.stringArray(forKey: Key.never) ?? [])
        set.remove(playbookID)
        defaults.set(Array(set), forKey: Key.never)
    }

    // MARK: Daily brief day stamp

    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func markBriefRan(on date: Date) {
        defaults.set(Self.dayStamp(date), forKey: Key.briefDay)
    }

    func briefAlreadyRan(on date: Date) -> Bool {
        defaults.string(forKey: Key.briefDay) == Self.dayStamp(date)
    }
}
