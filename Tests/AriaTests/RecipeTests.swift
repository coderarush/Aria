import XCTest
@testable import Aria

/// V11 P8+P17 — command recipes (deterministic, reusable workflows that skip
/// the planner) and workflow packs (persona bundles of recipes + agents).
final class RecipeTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recipes-\(UUID().uuidString).json")
    }

    private var sample: Recipe {
        Recipe(name: "Morning startup",
               steps: [
                RecipeStep(summary: "Open Calendar", tool: "open_app", input: ["name": "Calendar"]),
                RecipeStep(summary: "Open Mail", tool: "open_app", input: ["name": "Mail"]),
                RecipeStep(summary: "Compose the daily briefing", tool: "daily_briefing", input: [:])
               ])
    }

    // MARK: model

    func testRecipeMapsToPrebuiltTaskSteps() {
        let steps = sample.taskSteps()
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps[0].executor, .tool("open_app"))
        XCTAssertEqual(steps[0].input["name"], "Calendar")
        XCTAssertEqual(steps[2].executor, .tool("daily_briefing"))
        XCTAssertTrue(steps.allSatisfy { $0.status == .pending })
    }

    func testRecipeRoundTripsThroughJSON() throws {
        let recipe = sample   // capture once — `sample` mints a fresh id per access
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
    }

    // MARK: store + matching

    func testStorePersistsAcrossInstances() async {
        let url = tempURL()
        let store = RecipeStore(fileURL: url)
        await store.upsert(sample)
        let store2 = RecipeStore(fileURL: url)
        let all = await store2.all()
        XCTAssertEqual(all.map(\.name), ["Morning startup"])
    }

    func testMatchFindsRecipeByNameInCommand() async {
        let store = RecipeStore(fileURL: tempURL())
        await store.upsert(sample)
        let hit = await store.match(command: "run my morning startup")
        XCTAssertEqual(hit?.name, "Morning startup")
        let miss = await store.match(command: "what time is it")
        XCTAssertNil(miss)
    }

    func testMatchRequiresRunVerbOrExactPhrase() async {
        let store = RecipeStore(fileURL: tempURL())
        await store.upsert(Recipe(name: "Research", steps: [
            RecipeStep(summary: "s", tool: "web_search", input: [:])]))
        // A generic sentence merely containing a recipe word must NOT hijack.
        let miss = await store.match(command: "research the best USB mics")
        XCTAssertNil(miss)
        let hit = await store.match(command: "run my research recipe")
        XCTAssertEqual(hit?.name, "Research")
    }

    // MARK: packs

    func testBuiltinPacksExistForAllPersonas() {
        let names = WorkflowPack.builtins.map(\.persona)
        XCTAssertTrue(names.contains("Founder"))
        XCTAssertTrue(names.contains("Student"))
        XCTAssertTrue(names.contains("Developer"))
        for pack in WorkflowPack.builtins {
            XCTAssertFalse(pack.recipes.isEmpty, "\(pack.persona) pack has no recipes")
            for recipe in pack.recipes {
                XCTAssertFalse(recipe.steps.isEmpty, "\(recipe.name) has no steps")
            }
        }
    }

    func testPackInstallIsIdempotent() async {
        let url = tempURL()
        let store = RecipeStore(fileURL: url)
        let agentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-\(UUID().uuidString).json")
        let agents = AgentStore(fileURL: agentsURL)
        let pack = WorkflowPack.builtins.first { $0.persona == "Founder" }!

        await PackInstaller.install(pack, recipes: store, agents: agents)
        await PackInstaller.install(pack, recipes: store, agents: agents)

        let recipeNames = await store.all().map(\.name)
        XCTAssertEqual(recipeNames.count, Set(recipeNames).count, "duplicate recipes after re-install")
        let agentNames = await agents.all().map(\.name)
        XCTAssertEqual(agentNames.count, Set(agentNames).count, "duplicate agents after re-install")
    }

    func testPackToolsAllExistInRegistry() async {
        // Every tool a built-in pack references must actually be registered —
        // a pack that plans dead steps would fail on first run.
        let registry = ToolRegistry()
        for pack in WorkflowPack.builtins {
            for recipe in pack.recipes {
                for step in recipe.steps {
                    let exists = await registry.contains(step.tool)
                    XCTAssertTrue(exists, "\(recipe.name): tool '\(step.tool)' not registered")
                }
            }
        }
    }
}
