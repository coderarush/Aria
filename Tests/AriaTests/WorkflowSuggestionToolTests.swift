import XCTest
@testable import Aria

final class WorkflowSuggestionToolTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-suggestions-\(UUID().uuidString).json")
    }

    func testMeetingGoalSuggestsPrepWorkflow() {
        let suggestion = WorkflowSuggestionEngine.suggest(goal: "prep for investor meeting")
        XCTAssertEqual(suggestion.category, "meeting prep")
        XCTAssertEqual(suggestion.recipe.steps.map(\.tool), [
            "calendar", "notes_read", "recall_work", "daily_briefing"
        ])
        XCTAssertTrue(suggestion.stepText.contains("daily_briefing"))
    }

    func testInstallSavesRecipeWithNameOverride() async throws {
        let store = RecipeStore(fileURL: tempURL())
        let tool = WorkflowSuggestionTool(recipes: store)

        let result = try await tool.run(input: [
            "goal": "ship Aria website update",
            "persona": "AI Builder",
            "install": "true",
            "name": "ARIA ship loop"
        ])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Installed workflow"))
        let saved = await store.named("ARIA ship loop")
        XCTAssertEqual(saved?.name, "ARIA ship loop")
        XCTAssertEqual(saved?.packKey, "suggested")
        XCTAssertTrue(saved?.steps.contains(where: { $0.tool == "status" }) == true)
    }

    func testSuggestedRecipesOnlyUseRegisteredTools() async {
        let registry = ToolRegistry()
        let cases = [
            WorkflowSuggestionEngine.suggest(goal: "prep for investor meeting"),
            WorkflowSuggestionEngine.suggest(goal: "reply to important email"),
            WorkflowSuggestionEngine.suggest(goal: "research launch market"),
            WorkflowSuggestionEngine.suggest(goal: "ship a bug fix", persona: "developer"),
            WorkflowSuggestionEngine.suggest(goal: "make a launch video", persona: "creator"),
            WorkflowSuggestionEngine.suggest(goal: "organize my week")
        ]

        for suggestion in cases {
            for step in suggestion.recipe.steps {
                let exists = await registry.contains(step.tool)
                XCTAssertTrue(exists, "\(suggestion.recipe.name): \(step.tool) is not registered")
            }
        }
    }
}
