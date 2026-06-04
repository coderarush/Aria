import XCTest
@testable import Aria

@MainActor
final class WakeReArmTests: XCTestCase {
    func testEndConversationReturnsToCleanWakeState() {
        let w = WakeWordEngine()
        w.conversationActive = true
        w.isSuspended = true
        w.endConversation()
        XCTAssertFalse(w.conversationActive)
        XCTAssertFalse(w.isSuspended)
        XCTAssertTrue(w.isInWakeMode)
    }
}
