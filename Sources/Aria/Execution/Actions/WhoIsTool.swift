import Foundation

/// "Aria knows who you mean" — resolves a casual reference ("Sara", "the launch
/// deck") against the on-device entity graph and reports what Aria knows about
/// that person, project, place, or thing. Opt-in and local-only. Returns a
/// graceful "I don't know them yet" when there's no match or personalization is
/// off, so the model can ask the user instead of guessing.
struct WhoIsTool: AriaTool {
    static let name = "who_is"
    static let description = "Look up who or what the user is referring to — resolve a name or casual reference (e.g. 'Sara', 'the launch deck') against Aria's model of the user's people and projects, and report what Aria knows. Input: {name}. Use before drafting or acting on a reference to a person or project so you name the right one."
    static let paramHints: [String: String] = [
        "name": "The name or reference to resolve (e.g. 'Sara', 'the launch deck')"
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
            return .ok("Personalization is off, so I'm not keeping a model of your people and projects. Turn it on in Settings.")
        }
        guard let entity = await store.resolve(name) else {
            return .ok("I don't have anyone or anything matching “\(name)” yet. Tell me about them and I'll remember.")
        }
        var line = "\(entity.name) — \(entity.kind.rawValue)"
        if !entity.aliases.isEmpty {
            line += " (also: \(entity.aliases.joined(separator: ", ")))"
        }
        if !entity.notes.isEmpty {
            line += "\n  \(entity.notes)"
        }
        return .ok(line)
    }
}
