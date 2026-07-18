import XCTest
@testable import Aria

final class Part4GlassTests: XCTestCase {

    private func streamState(objective: String?) -> StreamState {
        StreamState(objective: objective, status: "executing",
                    attention: "flow", context: "writing", memory: ["m1"])
    }

    func testGlassStartsIdleAndIsGlassSurface() async {
        let glass = GlassRuntime()
        let state = await glass.state
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(glass.kind, .glass)
    }

    func testRenderBuildsHUDAndDisplays() async {
        let glass = GlassRuntime()
        await glass.render(streamState(objective: "plan week"))
        let state = await glass.state
        let hud = await glass.hud
        XCTAssertEqual(state, .displaying)
        XCTAssertEqual(hud.objective, "plan week")
        XCTAssertTrue(hud.canContinue)
        XCTAssertEqual(hud.memory, ["m1"])
        XCTAssertEqual(hud.context, "writing")
    }

    func testRenderWithoutObjectiveIsAware() async {
        let glass = GlassRuntime()
        await glass.render(streamState(objective: nil))
        let state = await glass.state
        XCTAssertEqual(state, .aware)
    }

    func testDismissReturnsIdleAndClears() async {
        let glass = GlassRuntime()
        await glass.render(streamState(objective: "x"))
        await glass.dismiss()
        let state = await glass.state
        let hud = await glass.hud
        XCTAssertEqual(state, .idle)
        XCTAssertNil(hud.objective)
    }

    func testSleepAndWake() async {
        let glass = GlassRuntime()
        await glass.sleep()
        var state = await glass.state
        XCTAssertEqual(state, .sleeping)
        await glass.wake()
        state = await glass.state
        XCTAssertEqual(state, .aware)
    }
}
