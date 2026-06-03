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
