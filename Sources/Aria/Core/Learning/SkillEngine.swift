import Foundation

/// One observed step in a workflow Aria is learning.
struct ObservedAction: Equatable, Sendable {
    let tool: String
    let input: [String: String]
    let summary: String
    let ok: Bool
}

/// An editable, confidence-scored workflow before it's saved.
struct SkillDraft: Equatable, Sendable {
    var name: String
    var steps: [RecipeStep]
    var confidence: Double

    func recipe(id: UUID = UUID()) -> Recipe { Recipe(id: id, name: name, steps: steps) }
}

/// SkillEngine (Phase 4): observe → compress → preview → save → execute. Learns a
/// reusable workflow from an action run. It introduces NO new persistence and NO
/// new execution path: a learned skill IS a `Recipe`, saved through the existing
/// `RecipeStore` and run through the existing `AutonomyEngine` prebuilt loop (same
/// Safety gates, same journaling). It synthesises *workflows*, never code — no
/// overlap with DynamicToolFactory. Skills are editable (draft.steps), reversible
/// (`forget`), and confidence-scored.
struct SkillEngine {
    private let store: RecipeStore

    init(store: RecipeStore = .shared) { self.store = store }

    /// Observe → compress: keep the successful steps, collapse consecutive repeats,
    /// score confidence by how clean the run was (success ratio).
    static func compress(_ actions: [ObservedAction], name: String) -> SkillDraft {
        let total = actions.count
        let successful = actions.filter(\.ok)
        var steps: [RecipeStep] = []
        for a in successful {
            if let last = steps.last, last.tool == a.tool, last.input == a.input { continue }
            steps.append(RecipeStep(summary: a.summary, tool: a.tool, input: a.input))
        }
        let confidence = total == 0 ? 0 : Double(successful.count) / Double(total)
        return SkillDraft(name: name, steps: steps, confidence: confidence)
    }

    /// Human-readable preview — shown before anything is saved or run.
    static func preview(_ draft: SkillDraft) -> String {
        let head = "Skill ‘\(draft.name)’ (confidence \(Int(draft.confidence * 100))%):"
        guard !draft.steps.isEmpty else { return head + "\n  (no steps)" }
        let lines = draft.steps.enumerated().map { i, s in "  \(i + 1). \(s.summary) [\(s.tool)]" }
        return ([head] + lines).joined(separator: "\n")
    }

    /// Save a draft as a Recipe (existing persistence). Returns the stored Recipe.
    @discardableResult
    func save(_ draft: SkillDraft) async -> Recipe {
        let recipe = draft.recipe()
        await store.upsert(recipe)
        return recipe
    }

    /// Reverse a save — skills are reversible.
    func forget(_ id: UUID) async { await store.remove(id) }
}
