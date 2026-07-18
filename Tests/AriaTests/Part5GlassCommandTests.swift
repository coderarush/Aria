import XCTest
@testable import Aria

final class Part5GlassCommandTests: XCTestCase {

    private func stream(objective: String?) -> StreamState {
        StreamState(objective: objective, status: "executing", attention: "flow",
                    context: "writing", memory: ["m"])
    }

    // MARK: - GlassExperience (§101) — display only, no execution

    func testDisplayObjectiveEntersFocusMode() async {
        let glass = GlassRuntime()
        let experience = GlassExperience(glass: glass)
        await experience.display(stream(objective: "plan week"))
        let mode = await experience.mode
        let hud = await glass.hud
        XCTAssertEqual(mode, .focus)
        XCTAssertEqual(hud.objective, "plan week")
    }

    func testNoObjectiveIsAmbient() async {
        let experience = GlassExperience(glass: GlassRuntime())
        await experience.display(stream(objective: nil))
        let mode = await experience.mode
        XCTAssertEqual(mode, .ambient)
    }

    func testShowRecallEntersRecallMode() async {
        let glass = GlassRuntime()
        let experience = GlassExperience(glass: glass)
        await experience.showRecall(RecallBundle(objective: "essay", summary: "drafting intro",
                                                 recentActions: ["draft"], artifacts: []))
        let mode = await experience.mode
        XCTAssertEqual(mode, .recall)
        let hud = await glass.hud
        XCTAssertEqual(hud.context, "drafting intro")
    }

    // MARK: - CommandModel (§102)

    func testParseCommands() {
        let model = CommandModel()
        XCTAssertEqual(model.parse("continue"), .continueWork)
        XCTAssertEqual(model.parse("handle this for me"), .handleThis)
        XCTAssertEqual(model.parse("what's the status"), .status)
        XCTAssertEqual(model.parse("pause"), .pause)
        XCTAssertEqual(model.parse("blah blah"), .unknown)
    }

    func testExternalTerseInternalDetailed() {
        let model = CommandModel()
        let external = model.externalResponse(for: .status)
        let internalReasoning = model.internalExplanation(for: .status)
        XCTAssertFalse(external.isEmpty)
        XCTAssertFalse(internalReasoning.isEmpty)
        XCTAssertLessThanOrEqual(external.count, 60)        // terse externally
        XCTAssertGreaterThanOrEqual(internalReasoning.count, external.count)  // explained internally
    }
}
