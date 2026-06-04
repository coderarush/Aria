import XCTest
@testable import Aria

final class IntentRouterTests: XCTestCase {
    func testMultiStepGoalIsTask() {
        XCTAssertTrue(IntentRouter.isTask("research the best mics and put a summary in notes"))
        XCTAssertTrue(IntentRouter.isTask("open mail, draft a reply to john, and send it"))
    }
    func testQuickQuestionIsChat() {
        XCTAssertFalse(IntentRouter.isTask("what time is it"))
        XCTAssertFalse(IntentRouter.isTask("fun fact about space"))
    }
}
