import XCTest
@testable import Aria

private struct StubHandler: CommandHandling {
    let response: AriaResponse
    func handle(command: String, privacyMode: Bool) async -> AriaResponse { response }
}

private struct StubRuntime: RuntimeExecutor {
    let output: String
    let succeeds: Bool
    func execute(_ request: BridgeRequest) async -> BridgeResult {
        BridgeResult(output: output, success: succeeds)
    }
}

final class AriaResponseBridgeTests: XCTestCase {

    private func richResponse() -> AriaResponse {
        AriaResponse(type: .action, message: "did the thing",
                     confidence: 0.77,
                     actions: [AgentAction(tool: "gmail", input: ["to": "a@b"])],
                     followup: "anything else?", succeeded: true)
    }

    func testLegacyReturnsByteIdenticalResponse() async {
        let original = richResponse()
        let bridge = AriaResponseBridge(stage: .legacy, legacy: StubHandler(response: original),
                                        runtime: StubRuntime(output: "X", succeeds: true), eventBus: EventBus())
        let result = await bridge.handle(command: "x", privacyMode: false)
        XCTAssertEqual(result, original)   // full struct equality — nothing lost
    }

    func testShadowServesLegacyAndEmitsComparison() async {
        let bus = EventBus()
        let original = richResponse()
        let bridge = AriaResponseBridge(stage: .shadow, legacy: StubHandler(response: original),
                                        runtime: StubRuntime(output: "different", succeeds: true), eventBus: bus)
        let result = await bridge.handle(command: "x", privacyMode: false)
        XCTAssertEqual(result, original)   // user still sees exact legacy response
        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.shadowCompared))
    }

    func testPreferredSynthesizesFromRuntimeOnSuccess() async {
        let bridge = AriaResponseBridge(stage: .preferred, legacy: StubHandler(response: richResponse()),
                                        runtime: StubRuntime(output: "runtime answer", succeeds: true), eventBus: EventBus())
        let result = await bridge.handle(command: "x", privacyMode: false)
        XCTAssertEqual(result.message, "runtime answer")
        XCTAssertTrue(result.succeeded)
    }

    func testPreferredFallsBackToLegacyOnRuntimeFailure() async {
        let original = richResponse()
        let bridge = AriaResponseBridge(stage: .preferred, legacy: StubHandler(response: original),
                                        runtime: StubRuntime(output: "", succeeds: false), eventBus: EventBus())
        let result = await bridge.handle(command: "x", privacyMode: false)
        XCTAssertEqual(result, original)
    }
}
