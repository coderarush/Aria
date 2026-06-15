import XCTest
@testable import Aria

final class PlaybookRecorderTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecorder() -> PlaybookRecorder {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-recipes-\(UUID().uuidString).json")
        let store = RecipeStore(fileURL: tempURL)
        return PlaybookRecorder(store: store)
    }

    private func validJSON(steps: [[String: Any]] = [
        ["summary": "Open Safari", "tool": "open_app", "input": ["app": "Safari"]],
        ["summary": "Search the web", "tool": "web_search", "input": ["query": "news"]]
    ]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: steps)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - teach() tests

    func testTeachParsesStepsFromJSON() async throws {
        let recorder = makeRecorder()
        let json = validJSON()
        let recipe = try await recorder.teach(
            name: "Morning Startup",
            description: "Open safari and search news",
            availableTools: "open_app: opens an app\nweb_search: searches the web",
            generateText: { _ in json }
        )
        XCTAssertEqual(recipe.name, "Morning Startup")
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertEqual(recipe.steps[0].tool, "open_app")
        XCTAssertEqual(recipe.steps[0].summary, "Open Safari")
        XCTAssertEqual(recipe.steps[0].input["app"], "Safari")
        XCTAssertEqual(recipe.steps[1].tool, "web_search")
    }

    func testTeachThrowsOnInvalidJSON() async throws {
        let recorder = makeRecorder()
        do {
            _ = try await recorder.teach(
                name: "Bad Recipe",
                description: "does stuff",
                availableTools: "some_tool: does something",
                generateText: { _ in "not json at all" }
            )
            XCTFail("Expected parseFailure to be thrown")
        } catch let error as PlaybookError {
            if case .parseFailure(let raw) = error {
                XCTAssertEqual(raw, "not json at all")
            } else {
                XCTFail("Expected parseFailure, got \(error)")
            }
        }
    }

    func testTeachThrowsOnEmptyStepsArray() async throws {
        let recorder = makeRecorder()
        do {
            _ = try await recorder.teach(
                name: "Empty Recipe",
                description: "nothing",
                availableTools: "some_tool: does something",
                generateText: { _ in "[]" }
            )
            XCTFail("Expected parseFailure to be thrown")
        } catch let error as PlaybookError {
            if case .parseFailure(let raw) = error {
                XCTAssertEqual(raw, "[]")
            } else {
                XCTFail("Expected parseFailure, got \(error)")
            }
        }
    }

    func testTeachExtractsJSONFromMessyResponse() async throws {
        let recorder = makeRecorder()
        let messyResponse = "Sure! Here you go: [{\"summary\":\"Do a step\",\"tool\":\"open_app\",\"input\":{}}] That's it!"
        let recipe = try await recorder.teach(
            name: "Messy Parse",
            description: "test messy JSON",
            availableTools: "open_app: opens an app",
            generateText: { _ in messyResponse }
        )
        XCTAssertEqual(recipe.steps.count, 1)
        XCTAssertEqual(recipe.steps[0].tool, "open_app")
        XCTAssertEqual(recipe.steps[0].summary, "Do a step")
        XCTAssertEqual(recipe.steps[0].input, [:])
    }

    func testTeachStepMissingInputDefaultsToEmpty() async throws {
        let recorder = makeRecorder()
        // Steps without "input" key should default to [:]
        let json = "[{\"summary\":\"Just do it\",\"tool\":\"notify\"}]"
        let recipe = try await recorder.teach(
            name: "No Input",
            description: "a step with no input",
            availableTools: "notify: sends a notification",
            generateText: { _ in json }
        )
        XCTAssertEqual(recipe.steps.count, 1)
        XCTAssertEqual(recipe.steps[0].input, [:])
    }

    // MARK: - list() tests

    func testListReturnsNamesAndStepCounts() async throws {
        let recorder = makeRecorder()
        // Seed two recipes
        _ = try await recorder.teach(
            name: "Morning Startup",
            description: "first workflow",
            availableTools: "open_app: opens an app",
            generateText: { _ in "[{\"summary\":\"s1\",\"tool\":\"open_app\",\"input\":{}},{\"summary\":\"s2\",\"tool\":\"open_app\",\"input\":{}}]" }
        )
        _ = try await recorder.teach(
            name: "Weekly Review",
            description: "second workflow",
            availableTools: "open_app: opens an app",
            generateText: { _ in "[{\"summary\":\"s1\",\"tool\":\"open_app\",\"input\":{}},{\"summary\":\"s2\",\"tool\":\"open_app\",\"input\":{}},{\"summary\":\"s3\",\"tool\":\"open_app\",\"input\":{}},{\"summary\":\"s4\",\"tool\":\"open_app\",\"input\":{}}]" }
        )
        let listing = await recorder.list()
        XCTAssertTrue(listing.contains("Morning Startup"), "Listing should contain recipe name")
        XCTAssertTrue(listing.contains("2 step"), "Listing should show step count")
        XCTAssertTrue(listing.contains("Weekly Review"), "Listing should contain second recipe name")
        XCTAssertTrue(listing.contains("4 step"), "Listing should show second step count")
    }

    func testListReturnsEmptyMessage() async {
        let recorder = makeRecorder()
        let listing = await recorder.list()
        XCTAssertTrue(listing.contains("No saved recipes"), "Should return empty message when no recipes")
    }

    // MARK: - delete() tests

    func testDeleteExistingRecipe() async throws {
        let recorder = makeRecorder()
        _ = try await recorder.teach(
            name: "Deletable",
            description: "to be deleted",
            availableTools: "open_app: opens an app",
            generateText: { _ in "[{\"summary\":\"step\",\"tool\":\"open_app\",\"input\":{}}]" }
        )
        let deleted = await recorder.delete(named: "Deletable")
        XCTAssertTrue(deleted, "delete() should return true for existing recipe")

        // Verify it's gone
        let listing = await recorder.list()
        XCTAssertTrue(listing.contains("No saved recipes") || !listing.contains("Deletable"))
    }

    func testDeleteNonexistentReturnsFalse() async {
        let recorder = makeRecorder()
        let deleted = await recorder.delete(named: "NonexistentRecipe")
        XCTAssertFalse(deleted, "delete() should return false for nonexistent recipe")
    }
}
