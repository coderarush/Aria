import XCTest
@testable import Aria

final class ModelsTests: XCTestCase {

    func testAriaResponseRoundTrip() throws {
        let original = AriaResponse(
            type: .action,
            message: "Opening Safari",
            confidence: 0.77,
            actions: [AgentAction(tool: "open_app", input: ["name": "Safari"])],
            followup: "Anything else?")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AriaResponse.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testTurnSucceededReflectsExecutionNotNarration() {
        // A turn "succeeds" only when it actually completed — not because the
        // model narrated a confident answer over a failed/declined action.
        XCTAssertTrue(AriaResponse.turnSucceeded(type: .answer, executionFailed: false))
        XCTAssertFalse(AriaResponse.turnSucceeded(type: .answer, executionFailed: true))
        XCTAssertFalse(AriaResponse.turnSucceeded(type: .clarify, executionFailed: false))
    }

    func testSucceededIsTransientExecutionState() throws {
        XCTAssertTrue(AriaResponse(type: .answer, message: "done").succeeded)          // default
        let failed = AriaResponse(type: .answer, message: "couldn't", succeeded: false)
        XCTAssertFalse(failed.succeeded)
        // succeeded is execution state, not part of the model JSON protocol, so a
        // decoded model response defaults to true (the orchestrator overrides it).
        let decoded = try JSONDecoder().decode(AriaResponse.self, from: JSONEncoder().encode(failed))
        XCTAssertTrue(decoded.succeeded)
    }

    func testKindRawValues() {
        XCTAssertEqual(AriaResponse.Kind.multiAction.rawValue, "multi_action")
        XCTAssertEqual(AriaResponse.Kind.answer.rawValue, "answer")
    }

    func testConversationTurnCodable() throws {
        let turn = ConversationTurn(
            transcript: "hi", responseMessage: "hello", responseType: .answer)
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(ConversationTurn.self, from: data)
        XCTAssertEqual(decoded, turn)
    }
}
