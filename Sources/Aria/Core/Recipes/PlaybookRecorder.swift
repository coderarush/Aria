import Foundation

enum PlaybookError: Error, Equatable {
    case parseFailure(raw: String)
    case missingName
}

/// V12 — converts plain-English workflow descriptions into saved Recipes via
/// the model, and provides list/delete management. `generateText` is injected
/// as a closure so unit tests can stub model responses without network calls.
actor PlaybookRecorder {
    static let shared = PlaybookRecorder()

    private let store: RecipeStore

    init(store: RecipeStore = .shared) {
        self.store = store
    }

    // MARK: - teach

    /// Parse a plain-English workflow description into RecipeSteps via the
    /// injected `generateText` closure, then persist as a Recipe.
    func teach(
        name: String,
        description: String,
        availableTools: String,
        generateText: @Sendable (String) async throws -> String
    ) async throws -> Recipe {
        let prompt = """
        Convert this workflow description into a JSON array of recipe steps.
        Only use tools from this list:
        \(availableTools)

        Workflow name: "\(name)"
        Description: "\(description)"

        Output ONLY valid JSON array, no markdown, no explanation:
        [{"summary":"step description","tool":"tool_name","input":{"key":"value"}},...]

        Rules:
        - Use only tool names from the list above
        - If a step has no matching tool, skip it
        - "input" may be empty {} if the tool needs no input
        - Output the JSON array only, starting with [ and ending with ]
        """

        let raw = try await generateText(prompt)

        // Extract JSON: find first [ and last ] to handle surrounding text
        guard
            let startIdx = raw.firstIndex(of: "["),
            let endIdx = raw.lastIndex(of: "]"),
            startIdx <= endIdx
        else {
            throw PlaybookError.parseFailure(raw: raw)
        }

        let jsonSubstring = String(raw[startIdx...endIdx])
        guard
            let jsonData = jsonSubstring.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            throw PlaybookError.parseFailure(raw: raw)
        }

        let steps: [RecipeStep] = parsed.compactMap { dict in
            guard
                let summary = dict["summary"] as? String,
                let tool = dict["tool"] as? String
            else { return nil }
            let input = dict["input"] as? [String: String] ?? [:]
            return RecipeStep(summary: summary, tool: tool, input: input)
        }

        guard !steps.isEmpty else {
            throw PlaybookError.parseFailure(raw: raw)
        }

        let recipe = Recipe(name: name, steps: steps)
        await store.upsert(recipe)
        return recipe
    }

    // MARK: - list

    /// Human-readable list of all saved recipes with step counts.
    func list() async -> String {
        let recipes = await store.all()
        guard !recipes.isEmpty else {
            return "No saved recipes yet. Teach me one!"
        }
        return recipes.enumerated()
            .map { idx, recipe in
                let count = recipe.steps.count
                let noun = count == 1 ? "step" : "steps"
                return "\(idx + 1). \(recipe.name) (\(count) \(noun))"
            }
            .joined(separator: "\n")
    }

    // MARK: - delete

    /// Delete a recipe by name (case-insensitive). Returns true if found and deleted.
    func delete(named name: String) async -> Bool {
        guard let recipe = await store.named(name) else { return false }
        await store.remove(recipe.id)
        return true
    }
}
