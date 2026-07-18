import Foundation

/// User-facing knobs for the Live Loop, persisted in UserDefaults. Master
/// switch + a per-recognizer autonomy tier (keyed by playbook id). Quiet hours
/// are shared with Proactive Presence (`ProactiveSettings`) so the user sets
/// them once.
struct LiveLoopSettings: Sendable, Equatable {
    var enabled: Bool
    /// Tier per playbook id; missing entries fall back to the playbook default.
    var tiers: [String: AutonomyTier]
    /// Pause the loop while macOS Low Power Mode is on.
    var pauseInLowPower: Bool
    /// Idle tick cadence, seconds (evaluations also run on signal events).
    var tickSeconds: TimeInterval

    func tier(for playbookID: String) -> AutonomyTier {
        tiers[playbookID] ?? PlaybookLibrary.all[playbookID]?.defaultTier ?? .off
    }

    private enum Key {
        static let enabled = "liveloop.enabled"
        static let lowPower = "liveloop.pauseInLowPower"
        static let tick = "liveloop.tickSeconds"
        static func tier(_ id: String) -> String { "liveloop.tier.\(id)" }
    }

    static func load(_ defaults: UserDefaults = .standard) -> LiveLoopSettings {
        var tiers: [String: AutonomyTier] = [:]
        for id in PlaybookLibrary.all.keys {
            if let raw = defaults.string(forKey: Key.tier(id)),
               let tier = AutonomyTier(rawValue: raw) {
                tiers[id] = tier
            }
        }
        return LiveLoopSettings(
            enabled: defaults.object(forKey: Key.enabled) as? Bool ?? true,
            tiers: tiers,
            pauseInLowPower: defaults.object(forKey: Key.lowPower) as? Bool ?? true,
            tickSeconds: defaults.object(forKey: Key.tick) as? TimeInterval ?? 45)
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(pauseInLowPower, forKey: Key.lowPower)
        defaults.set(tickSeconds, forKey: Key.tick)
        for (id, tier) in tiers {
            defaults.set(tier.rawValue, forKey: Key.tier(id))
        }
    }
}
