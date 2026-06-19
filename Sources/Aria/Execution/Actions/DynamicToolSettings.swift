import Foundation

/// User-facing toggles for the dynamic tool system, persisted in UserDefaults.
/// Mirrors the "Dynamic Tools" settings section in the spec.
struct DynamicToolSettings {
    var allowCodeExecution: Bool
    var showCodeBeforeRun: Bool
    var askBeforeSaving: Bool
    var syncCommunityTools: Bool

    private enum Key {
        static let allow = "dyn.allowCodeExecution"
        static let show = "dyn.showCodeBeforeRun"
        static let ask = "dyn.askBeforeSaving"
        static let sync = "dyn.syncCommunityTools"
    }

    static func load(_ defaults: UserDefaults = .standard) -> DynamicToolSettings {
        DynamicToolSettings(
            allowCodeExecution: defaults.object(forKey: Key.allow) as? Bool ?? true,
            showCodeBeforeRun: defaults.object(forKey: Key.show) as? Bool ?? false,
            askBeforeSaving: defaults.object(forKey: Key.ask) as? Bool ?? true,
            syncCommunityTools: defaults.object(forKey: Key.sync) as? Bool ?? false)
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(allowCodeExecution, forKey: Key.allow)
        defaults.set(showCodeBeforeRun, forKey: Key.show)
        defaults.set(askBeforeSaving, forKey: Key.ask)
        defaults.set(syncCommunityTools, forKey: Key.sync)
    }
}
