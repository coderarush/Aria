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

    func testEndsOnPunctuatedDismissPhrase() {
        var ended = false
        let s = ConversationSession(onEnd: { ended = true })
        s.start()
        s.userSaid("Thanks, Aria!")
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

    func testDismissWordsInsideARequestDoNotEndConversation() {
        var handled: [String] = []
        let s = ConversationSession(onEnd: {}, onTurn: { handled.append($0) })
        s.start()
        s.userSaid("How do I stop Safari from reloading?")
        s.userSaid("That's all the context, now draft it")
        XCTAssertEqual(handled, [
            "How do I stop Safari from reloading?",
            "That's all the context, now draft it",
        ])
        XCTAssertFalse(s.hasEnded)
    }
}
