import Foundation

/// Ways into Aria (spec §118).
enum EntryPoint: String, Sendable, CaseIterable {
    case hotkey, menuBar, voice, continueSession, glass
}

/// The default surface (spec §118): objective first, chat second — Aria looks
/// operational, not conversational.
struct DefaultExperience: Sendable {

    let entryPoints: [EntryPoint] = EntryPoint.allCases

    /// Ordered surface components for an entry point — objective leads, chat
    /// trails.
    func surface(for entry: EntryPoint) -> [String] {
        ["objective", "actions", "continue", "chat"]
    }
}
