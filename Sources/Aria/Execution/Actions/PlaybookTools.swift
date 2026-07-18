import Foundation

/// Teach Aria a new named workflow by describing it in plain English.
struct RecipeTeachTool: AriaTool {
    static let name = "recipe_teach"
    static let description = "Save a new workflow recipe by describing its steps. Input: name (recipe name), description (plain-English description of the steps to perform)."
    static let paramHints: [String: String] = [
        "name": "The name for this recipe (e.g. 'Morning startup')",
        "description": "Plain-English description of the steps to perform"
    ]

    private let gemini: GeminiClient

    init(gemini: GeminiClient = GeminiClient()) {
        self.gemini = gemini
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"], !name.isEmpty else {
            return .ok("Please provide a name for the recipe.")
        }
        let description = input["description"] ?? ""
        guard !description.isEmpty else {
            return .ok("Please describe the steps for recipe '\(name)'.")
        }
        let catalog = await ToolRegistry().catalog()
        do {
            let recipe = try await PlaybookRecorder.shared.teach(
                name: name,
                description: description,
                availableTools: catalog,
                generateText: { prompt in try await self.gemini.generateText(prompt: prompt, temperature: 0) }
            )
            let count = recipe.steps.count
            let noun = count == 1 ? "step" : "steps"
            return .ok("Saved recipe '\(recipe.name)' with \(count) \(noun).")
        } catch PlaybookError.parseFailure {
            return .fail("Could not parse a workflow from that description. Try describing each step more explicitly.")
        }
    }
}

/// List all saved workflow recipes.
struct RecipeListTool: AriaTool {
    static let name = "recipe_list"
    static let description = "List all saved workflow recipes."

    func run(input: [String: String]) async throws -> ToolResult {
        .ok(await PlaybookRecorder.shared.list())
    }
}

/// Delete a saved workflow recipe by name.
struct RecipeDeleteTool: AriaTool {
    static let name = "recipe_delete"
    static let description = "Delete a saved workflow recipe by name. Input: name."
    static let paramHints: [String: String] = [
        "name": "The name of the recipe to delete"
    ]
    var isDestructive: Bool { true }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"], !name.isEmpty else {
            return .ok("Please provide the name of the recipe to delete.")
        }
        let deleted = await PlaybookRecorder.shared.delete(named: name)
        return deleted
            ? .ok("Deleted recipe '\(name)'.")
            : .ok("No recipe named '\(name)' found.")
    }
}
