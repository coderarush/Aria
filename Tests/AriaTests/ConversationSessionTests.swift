import XCTest
@testable import Aria

@MainActor
final class ConversationSessionTests: XCTestCase {
    func testEndsOnDismissPhrase() {
        var ended = false
        let s = ConversationSession(onEnd: { ended = true })
        s.start()
        s.userSaid("thanks aria")
        XCTAssertTrue(ended)
    }

    func testRoutesNormalTurnToHandler() {
        var handled: [String] = []
        let s = ConversationSession(onEnd: {}, onTurn: { handled.append($0) })
        s.start()
        s.userSaid("what time is it")
        XCTAssertEqual(handled, ["what time is it"])
        XCTAssertFalse(s.hasEnded)
    }
}
