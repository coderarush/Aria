import Foundation

/// Suggests or installs a reusable workflow from a high-level goal. This gives
/// Aria a deterministic "make this repeatable" move without needing the model
/// to invent recipe JSON on every run.
struct WorkflowSuggestionTool: AriaTool {
    static let name = "workflow_suggest"
    static let description = "Suggest or install a reusable workflow recipe from a high-level goal. Input: {goal, persona?, install?, name?}. Use when the user asks to automate, repeat, make a routine, or create a workflow."
    static let paramHints: [String: String] = [
        "goal": "The outcome or routine the user wants to make repeatable",
        "persona": "Optional persona/context: founder, student, developer, creator, AI builder",
        "install": "true to save the suggested recipe",
        "name": "Optional recipe name override when installing"
    ]

    private let recipes: RecipeStore

    init(recipes: RecipeStore = .shared) {
        self.recipes = recipes
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let rawGoal = input["goal"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawGoal.isEmpty else { return .fail("Missing input: goal") }

        var suggestion = WorkflowSuggestionEngine.suggest(goal: rawGoal, persona: input["persona"])
        if let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            suggestion.recipe = Recipe(name: name, steps: suggestion.recipe.steps, packKey: suggestion.recipe.packKey)
        }

        let shouldInstall = ["true", "yes", "1", "install"].contains((input["install"] ?? "").lowercased())
        if shouldInstall {
            await recipes.upsert(suggestion.recipe)
        }

        let verb = shouldInstall ? "Installed" : "Suggested"
        return .ok("\(verb) workflow “\(suggestion.recipe.name)” for \(suggestion.category).\n\(suggestion.summary)\n\nSteps:\n\(suggestion.stepText)")
    }
}

struct WorkflowSuggestion: Equatable {
    var category: String
    var summary: String
    var recipe: Recipe

    var stepText: String {
        recipe.steps.enumerated()
            .map { index, step in
                let inputs = step.input.isEmpty
                    ? ""
                    : " " + step.input.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                return "\(index + 1). \(step.summary) — \(step.tool)\(inputs)"
            }
            .joined(separator: "\n")
    }
}

enum WorkflowSuggestionEngine {
    static func suggest(goal: String, persona: String? = nil) -> WorkflowSuggestion {
        let normalized = goal.lowercased()
        let personaKey = persona?.lowercased() ?? ""

        if normalized.contains(anyOf: ["meeting", "call", "interview", "prep"]) {
            return meetingPrep(goal: goal)
        }
        if normalized.contains(anyOf: ["email", "inbox", "reply", "follow up", "follow-up"]) {
            return inboxLoop(goal: goal)
        }
        if normalized.contains(anyOf: ["research", "learn", "compare", "market"]) {
            return researchSprint(goal: goal)
        }
        if normalized.contains(anyOf: ["ship", "release", "bug", "code", "test", "github"])
            || personaKey.contains("developer")
            || personaKey.contains("builder") {
            return shipLoop(goal: goal)
        }
        if normalized.contains(anyOf: ["content", "post", "launch", "video", "script", "creator"])
            || personaKey.contains("creator") {
            return creatorLoop(goal: goal)
        }
        return executiveLoop(goal: goal)
    }

    private static func meetingPrep(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "meeting prep",
            summary: "A repeatable prep loop: calendar context, notes, recent work, and a briefing.",
            recipe: Recipe(name: "Meeting prep: \(shortName(goal))", steps: [
                RecipeStep(summary: "Check today's calendar", tool: "calendar", input: ["range": "today"]),
                RecipeStep(summary: "Pull relevant notes", tool: "notes_read", input: ["query": goal]),
                RecipeStep(summary: "Recall recent project work", tool: "recall_work", input: ["timeframe": "this week"]),
                RecipeStep(summary: "Generate the briefing", tool: "daily_briefing", input: [:])
            ], packKey: "suggested"))
    }

    private static func inboxLoop(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "inbox follow-up",
            summary: "A communication loop: recent mail, relevant search, draft assistance, and follow-up tracking.",
            recipe: Recipe(name: "Inbox loop: \(shortName(goal))", steps: [
                RecipeStep(summary: "Read recent Gmail", tool: "gmail_recent", input: ["limit": "10"]),
                RecipeStep(summary: "Search matching email", tool: "email_search", input: ["query": goal]),
                RecipeStep(summary: "Draft smart replies", tool: "smart_reply", input: ["tone": "clear concise"]),
                RecipeStep(summary: "Check follow-ups", tool: "followup_check", input: [:])
            ], packKey: "suggested"))
    }

    private static func researchSprint(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "research sprint",
            summary: "A research loop: search, synthesize, save, and make the outcome reusable.",
            recipe: Recipe(name: "Research sprint: \(shortName(goal))", steps: [
                RecipeStep(summary: "Research the topic", tool: "research", input: ["query": goal]),
                RecipeStep(summary: "Search local knowledge", tool: "knowledge_search", input: ["query": goal]),
                RecipeStep(summary: "Save findings", tool: "save_note", input: ["title": "Research — \(shortName(goal))"]),
                RecipeStep(summary: "Remember the research", tool: "remember_entity",
                           input: ["name": "Research: \(shortName(goal))",
                                   "kind": "thing",
                                   "notes": "Research completed: \(goal)"])
            ], packKey: "suggested"))
    }

    private static func shipLoop(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "ship loop",
            summary: "A build loop: recover context, inspect work, check status, and wrap with a ship log.",
            recipe: Recipe(name: "Ship loop: \(shortName(goal))", steps: [
                RecipeStep(summary: "Recover project status", tool: "status", input: ["project": goal]),
                RecipeStep(summary: "Recall recent work", tool: "recall_work", input: ["timeframe": "this week"]),
                RecipeStep(summary: "List saved workflows", tool: "recipe_list", input: [:]),
                RecipeStep(summary: "Prepare ship review", tool: "daily_review", input: [:])
            ], packKey: "suggested"))
    }

    private static func creatorLoop(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "creator launch",
            summary: "A creator loop: collect ideas, research, improve the draft, and track responses.",
            recipe: Recipe(name: "Creator loop: \(shortName(goal))", steps: [
                RecipeStep(summary: "Pull idea notes", tool: "notes_read", input: ["query": goal]),
                RecipeStep(summary: "Research the angle", tool: "research", input: ["query": goal]),
                RecipeStep(summary: "Improve the draft", tool: "draft_feedback", input: ["goal": "make this sharper and more memorable"]),
                RecipeStep(summary: "Check follow-ups", tool: "followup_check", input: [:])
            ], packKey: "suggested"))
    }

    private static func executiveLoop(goal: String) -> WorkflowSuggestion {
        WorkflowSuggestion(
            category: "executive loop",
            summary: "A default outcome loop: status, context, next action, and review.",
            recipe: Recipe(name: "Execution loop: \(shortName(goal))", steps: [
                RecipeStep(summary: "Check status", tool: "status", input: ["project": goal]),
                RecipeStep(summary: "Recall recent context", tool: "recall_work", input: ["timeframe": "this week"]),
                RecipeStep(summary: "Create or advance the goal", tool: "goal", input: ["action": "create", "title": goal]),
                RecipeStep(summary: "Review progress", tool: "daily_review", input: [:])
            ], packKey: "suggested"))
    }

    private static func shortName(_ goal: String) -> String {
        let words = goal
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(5)
            .joined(separator: " ")
        return words.isEmpty ? "New workflow" : words
    }
}

private extension String {
    func contains(anyOf needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
