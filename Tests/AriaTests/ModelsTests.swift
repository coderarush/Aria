import XCTest
@testable import Aria

final class ModelsTests: XCTestCase {

    func testFridayResponseRoundTrip() throws {
        let original = FridayResponse(
            type: .action,
            message: "Opening Safari",
            confidence: 0.77,
            actions: [AgentAction(tool: "open_app", input: ["name": "Safari"])],
            followup: "Anything else?")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FridayResponse.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testKindRawValues() {
        XCTAssertEqual(FridayResponse.Kind.multiAction.rawValue, "multi_action")
        XCTAssertEqual(FridayResponse.Kind.answer.rawValue, "answer")
    }

    func testConversationTurnCodable() throws {
        let turn = ConversationTurn(
            transcript: "hi", responseMessage: "hello", responseType: .answer)
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(ConversationTurn.self, from: data)
        XCTAssertEqual(decoded, turn)
    }
}
