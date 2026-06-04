import XCTest
@testable import Aria

final class MemoryCaptureTests: XCTestCase {
    func testExtractsRememberCommands() {
        XCTAssertEqual(MemoryCapture.extract("Remember that I prefer dark mode"), "I prefer dark mode")
        XCTAssertEqual(MemoryCapture.extract("remember my birthday is in May"), "my birthday is in May")
        XCTAssertEqual(MemoryCapture.extract("Don't forget that the wifi password is hunter2"),
                       "the wifi password is hunter2")
        XCTAssertEqual(MemoryCapture.extract("note that I'm allergic to peanuts."), "I'm allergic to peanuts")
    }

    func testIgnoresNonRememberCommands() {
        XCTAssertNil(MemoryCapture.extract("what's the weather"))
        XCTAssertNil(MemoryCapture.extract("open Spotify"))
        XCTAssertNil(MemoryCapture.extract("remember"))   // nothing to remember
    }

    func testIgnoresQuestionsAndRecall() {
        XCTAssertNil(MemoryCapture.extract("remember when we talked about the project?"))
        XCTAssertNil(MemoryCapture.extract("remember how to get to the airport?"))
        XCTAssertNil(MemoryCapture.extract("remember what I said earlier"))   // "what" → recall
        XCTAssertNil(MemoryCapture.extract("remember to buy milk"))           // "to" → a task
    }
}
