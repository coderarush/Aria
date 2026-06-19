import Foundation

/// User configuration for the Local Knowledge Engine: which folders Aria may
/// index, and the master switch. Off by default — indexing the user's documents
/// is strictly opt-in (privacy-first).
struct KnowledgeSettings {
    var enabled: Bool
    /// Folder paths (may contain ~). Order is the user's display order.
    var folders: [String]

    private enum Key {
        static let enabled = "knowledge.enabled"
        static let folders = "knowledge.folders"
    }

    static func load(_ defaults: UserDefaults = .standard) -> KnowledgeSettings {
        KnowledgeSettings(
            enabled: defaults.object(forKey: Key.enabled) as? Bool ?? false,
            folders: defaults.stringArray(forKey: Key.folders) ?? [])
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(folders, forKey: Key.folders)
    }
}
