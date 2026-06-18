import XCTest
@testable import Aria

final class SkillEngineTests: XCTestCase {

    private func store() -> RecipeStore {
        RecipeStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-skill-\(UUID().uuidString).json"))
    }
    private func act(_ tool: String, _ input: [String: String] = [:], _ summary: String = "", ok: Bool = true) -> ObservedAction {
        ObservedAction(tool: tool, input: input, summary: summary.isEmpty ? tool : summary, ok: ok)
    }

    func testCompressDropsFailuresAndDedupesConsecutive() {
        let actions = [
            act("open_app", ["name": "Mail"], "open Mail"),
            act("open_app", ["name": "Mail"], "open Mail"),     // dup → collapse
            act("send", [:], "send", ok: false),                // failed → drop
            act("archive", [:], "archive")
        ]
        let draft = SkillEngine.compress(actions, name: "Inbox zero")
        XCTAssertEqual(draft.steps.map(\.tool), ["open_app", "archive"])
    }

    func testConfidenceIsSuccessRatio() {
        let actions = [act("a"), act("b", ok: false), act("c"), act("d")]   // 3/4 ok
        let draft = SkillEngine.compress(actions, name: "s")
        XCTAssertEqual(draft.confidence, 0.75, accuracy: 0.0001)
    }

    func testEmptyObservationIsZeroConfidence() {
        let draft = SkillEngine.compress([], name: "s")
        XCTAssertEqual(draft.confidence, 0)
        XCTAssertTrue(draft.steps.isEmpty)
    }

    func testDraftIsEditableBeforeSave() async {
        let s = store(); let engine = SkillEngine(store: s)
        var draft = SkillEngine.compress([act("a", [:], "step a")], name: "s")
        draft.steps.append(RecipeStep(summary: "manual", tool: "extra"))   // user edits
        let recipe = await engine.save(draft)
        XCTAssertEqual(recipe.steps.map(\.tool), ["a", "extra"])
    }

    func testSavePersistsViaRecipeStore() async {
        let s = store(); let engine = SkillEngine(store: s)
        let draft = SkillEngine.compress([act("a", [:], "do a")], name: "Morning")
        _ = await engine.save(draft)
        let found = await s.named("Morning")
        XCTAssertNotNil(found)                       // reuses existing recipe persistence
        XCTAssertEqual(found?.steps.first?.tool, "a")
    }

    func testForgetIsReversible() async {
        let s = store(); let engine = SkillEngine(store: s)
        let recipe = await engine.save(SkillEngine.compress([act("a")], name: "Temp"))
        await engine.forget(recipe.id)
        let gone = await s.named("Temp")
        XCTAssertNil(gone)
    }

    func testPreviewListsStepsAndConfidence() {
        let draft = SkillEngine.compress([act("open_app", ["name": "Mail"], "open Mail"),
                                          act("archive", [:], "archive all")], name: "Inbox zero")
        let preview = SkillEngine.preview(draft)
        XCTAssertTrue(preview.contains("Inbox zero"))
        XCTAssertTrue(preview.contains("open Mail"))
        XCTAssertTrue(preview.contains("archive all"))
        XCTAssertTrue(preview.contains("%"))
    }
}
