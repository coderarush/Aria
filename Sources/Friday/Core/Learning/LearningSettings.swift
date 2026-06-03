import Foundation

/// Toggles for behavioral learning ("Friday's Brain"), persisted in UserDefaults.
struct LearningSettings {
    var enabled: Bool
    /// Master kill switch — stops all automations instantly.
    var automationsPaused: Bool
    /// Confidence required to surface a pattern: 0.6 aggressive … 0.9 conservative.
    var sensitivity: Double

    private enum Key {
        static let enabled = "brain.enabled"
        static let paused = "brain.automationsPaused"
        static let sensitivity = "brain.sensitivity"
    }

    static func load(_ defaults: UserDefaults = .standard) -> LearningSettings {
        LearningSettings(
            enabled: defaults.object(forKey: Key.enabled) as? Bool ?? true,
            automationsPaused: defaults.object(forKey: Key.paused) as? Bool ?? false,
            sensitivity: defaults.object(forKey: Key.sensitivity) as? Double ?? 0.75)
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(automationsPaused, forKey: Key.paused)
        defaults.set(sensitivity, forKey: Key.sensitivity)
    }
}
