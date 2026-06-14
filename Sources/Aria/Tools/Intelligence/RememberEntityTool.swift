import Foundation

/// "Aria builds a model of YOU" — records a person, project, place, or thing the
/// user refers to into the on-device entity graph, so later references ("Sara",
/// "the launch deck") resolve to the right node. Opt-in and local-only; nothing
/// leaves the machine. A no-op when personalization is off.
struct RememberEntityTool: AriaTool {
    static let name = "remember_entity"
    static let description = "Remember a person, project, place, or thing the user refers to, so Aria can recognize later references to it. Input: {name, kind, notes}. kind is one of person/project/place/thing. Use when the user introduces or describes someone or something Aria should know (e.g. 'Sara is my designer', 'the launch deck is the Q3 keynote')."
    static let paramHints: [String: String] = [
        "name": "The canonical name of the person/project/place/thing (e.g. 'Sara Lin', 'Launch deck')",
        "kind": "One of: person, project, place, thing",
        "notes": "What to remember about it (role, context, aliases the user uses)"
    ]

    private let store: EntityStore

    init(store: EntityStore = .shared) {
        self.store = store
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw ToolError.missingInput("name")
        }
        guard await store.isEnabled else {
            return .ok("Personalization is off. Turn it on in Settings to let me build a model of the people and projects you work with.")
        }
        let kind = EntityKind(rawValue: (input["kind"] ?? "thing").lowercased()) ?? .thing
        let notes = input["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entity = Entity(name: name, kind: kind, notes: notes)
        guard let stored = await store.upsert(entity) else {
            // Gated mid-flight (shouldn't happen after the isEnabled check, but
            // upsert is the source of truth for the privacy gate).
            return .ok("Personalization is off, so I didn't save that.")
        }
        let noteSuffix = stored.notes.isEmpty ? "" : " — \(stored.notes)"
        return .ok("Got it. I'll remember \(stored.name) (\(stored.kind.rawValue))\(noteSuffix).")
    }
}
