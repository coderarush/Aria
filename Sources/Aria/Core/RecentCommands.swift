import Foundation

/// The command palette's recents: last eight typed commands, newest first,
/// deduplicated (re-running moves to front). Plain UserDefaults — these are
/// commands the user typed, not secrets.
enum RecentCommands {
    static let key = "app.recentCommands"
    static let cap = 8

    static func record(_ command: String, defaults: UserDefaults = .standard) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = all(defaults: defaults)
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(cap)), forKey: key)
    }

    static func all(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
