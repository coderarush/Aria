import XCTest
@testable import Aria

private struct FakeLegacy: LegacyExecutor {
    let output: String
    func execute(_ request: BridgeRequest) async -> BridgeResult {
        BridgeResult(output: output, success: true, duration: 0.01)
    }
}

private struct FakeRuntime: RuntimeExecutor {
    let output: String
    let succeeds: Bool
    func execute(_ request: BridgeRequest) async -> BridgeResult {
        BridgeResult(output: output, success: succeeds, duration: 0.005)
    }
}

final class Part3BridgeTests: XCTestCase {

    private func bridge(_ stage: MigrationStage,
                        legacy: String = "L",
                        runtime: String = "R",
                        runtimeSucceeds: Bool = true,
                        bus: EventBus = EventBus()) -> RuntimeBridge {
        RuntimeBridge(stage: stage,
                      legacy: FakeLegacy(output: legacy),
                      runtime: FakeRuntime(output: runtime, succeeds: runtimeSucceeds),
                      eventBus: bus)
    }

    func testLegacyStageServesLegacy() async {
        let outcome = await bridge(.legacy).execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .legacy)
        XCTAssertEqual(outcome.output, "L")
        XCTAssertNil(outcome.diff)
    }

    func testShadowServesLegacyAndProducesDiffAndEmits() async {
        let bus = EventBus()
        let outcome = await bridge(.shadow, bus: bus).execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .legacy)
        XCTAssertEqual(outcome.output, "L")
        XCTAssertNotNil(outcome.diff)
        XCTAssertFalse(outcome.diff!.equal)   // "L" != "R"
        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.shadowCompared))
    }

    func testShadowEqualOutputsMarkDiffEqual() async {
        let outcome = await bridge(.shadow, legacy: "same", runtime: "same")
            .execute(BridgeRequest(objective: "x"))
        XCTAssertTrue(outcome.diff!.equal)
    }

    func testPreferredServesRuntime() async {
        let outcome = await bridge(.preferred).execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .runtime)
        XCTAssertEqual(outcome.output, "R")
    }

    func testPreferredFallsBackWhenRuntimeFails() async {
        let outcome = await bridge(.preferred, runtimeSucceeds: false)
            .execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .legacy)
        XCTAssertEqual(outcome.output, "L")
    }

    func testRuntimeOnlyServesRuntime() async {
        let outcome = await bridge(.runtimeOnly).execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .runtime)
    }

    func testSetStageMutates() async {
        let b = bridge(.legacy)
        await b.setStage(.preferred)
        let outcome = await b.execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .runtime)
    }
}
