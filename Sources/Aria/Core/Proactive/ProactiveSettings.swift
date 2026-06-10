import Foundation

/// A daily window during which Aria stays silent (no proactive surfacing).
/// `endHour` is exclusive. Supports overnight wrap (e.g. 22 → 7).
struct QuietHours: Equatable {
    var startHour: Int
    var endHour: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        // overnight wrap
        return hour >= startHour || hour < endHour
    }
}

/// User-facing toggles for the Proactive Presence engine, persisted in UserDefaults.
/// Master switch + per-source opt-in + a quiet-hours window. Screen source is OFF
/// by default for privacy (it reads focused content).
struct ProactiveSettings {
    var enabled: Bool
    var sourceEnabled: [SuggestionSource: Bool]
    var quietHoursEnabled: Bool
    var quietHours: QuietHours

    func isSourceEnabled(_ source: SuggestionSource) -> Bool {
        sourceEnabled[source] ?? false
    }

    private enum Key {
        static let enabled = "proactive.enabled"
        static let quietEnabled = "proactive.quietHoursEnabled"
        static let quietStart = "proactive.quietStartHour"
        static let quietEnd = "proactive.quietEndHour"
        static func source(_ s: SuggestionSource) -> String { "proactive.source.\(s.rawValue)" }
    }

    /// Per-source defaults: calendar/routine/command on, screen off (privacy).
    private static func defaultEnabled(_ s: SuggestionSource) -> Bool {
        s != .screen
    }

    static func load(_ defaults: UserDefaults = .standard) -> ProactiveSettings {
        var sources: [SuggestionSource: Bool] = [:]
        for s in SuggestionSource.allCases {
            sources[s] = defaults.object(forKey: Key.source(s)) as? Bool ?? defaultEnabled(s)
        }
        return ProactiveSettings(
            enabled: defaults.object(forKey: Key.enabled) as? Bool ?? true,
            sourceEnabled: sources,
            quietHoursEnabled: defaults.object(forKey: Key.quietEnabled) as? Bool ?? false,
            quietHours: QuietHours(
                startHour: defaults.object(forKey: Key.quietStart) as? Int ?? 22,
                endHour: defaults.object(forKey: Key.quietEnd) as? Int ?? 7))
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.enabled)
        for s in SuggestionSource.allCases {
            defaults.set(isSourceEnabled(s), forKey: Key.source(s))
        }
        defaults.set(quietHoursEnabled, forKey: Key.quietEnabled)
        defaults.set(quietHours.startHour, forKey: Key.quietStart)
        defaults.set(quietHours.endHour, forKey: Key.quietEnd)
    }
}
