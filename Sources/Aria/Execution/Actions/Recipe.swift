import Foundation

/// V11 P8 — one deterministic step of a command recipe: a registered tool
/// with fixed inputs. Recipes skip the model planner entirely, so a recipe
/// runs the same way every time.
struct RecipeStep: Codable, Equatable, Sendable {
    var summary: String
    var tool: String
    var input: [String: String]

    init(summary: String, tool: String, input: [String: String] = [:]) {
        self.summary = summary
        self.tool = tool
        self.input = input
    }
}

/// V11 P8 — a reusable, named workflow ("Morning startup"). Executes through
/// the normal AutonomyEngine loop — same Safety gates, same journaling, same
/// task panel — but with a pre-built plan instead of a model-planned one.
struct Recipe: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var steps: [RecipeStep]
    /// Which built-in pack installed this (nil for user-created). Lets a pack
    /// re-install update its own recipes without touching the user's.
    var packKey: String?

    init(id: UUID = UUID(), name: String, steps: [RecipeStep], packKey: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.packKey = packKey
    }

    /// The pre-built plan for the engine.
    func taskSteps() -> [TaskStep] {
        steps.map { TaskStep(summary: $0.summary, executor: .tool($0.tool), input: $0.input) }
    }

    /// Cheap, synchronous "does this command even smell like a recipe
    /// invocation?" — the router uses it to pick the task path; the store's
    /// match() then does the real (conservative) resolution.
    static func invocationLikely(_ command: String) -> Bool {
        let l = command.lowercased()
        if l.contains("recipe") || l.contains("routine") { return true }
        return ["run my ", "start my ", "do my "].contains { l.contains($0) }
    }
}

/// Persisted set of recipes, mirroring AgentStore's shape.
actor RecipeStore {
    static let shared = RecipeStore()

    private let fileURL: URL
    private var recipes: [Recipe]

    init(fileURL: URL? = nil) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("recipes.json")
        self.fileURL = url
        self.recipes = Self.load(from: url)
    }

    func all() -> [Recipe] { recipes }

    func upsert(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
        save()
    }

    func remove(_ id: UUID) {
        recipes.removeAll { $0.id == id }
        save()
    }

    func named(_ name: String) -> Recipe? {
        recipes.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Match a spoken/typed command to a recipe. Deliberately conservative:
    /// the user must use a run-style verb ("run/start/do my X") or say the
    /// recipe name with "recipe"/"routine" — a sentence that merely contains
    /// a recipe word must never hijack a normal task.
    func match(command: String) -> Recipe? {
        let lower = command.lowercased()
        for recipe in recipes {
            let name = recipe.name.lowercased()
            guard lower.contains(name) else { continue }
            let runVerbs = ["run ", "start ", "do my ", "run my ", "start my "]
            let hasVerb = runVerbs.contains { lower.contains($0 + name) || lower.contains($0 + "my " + name) }
            let hasNoun = lower.contains(name + " recipe") || lower.contains(name + " routine")
                || lower.contains("recipe") || lower.contains("routine")
            if hasVerb || hasNoun { return recipe }
        }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recipes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [Recipe] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
    }
}
