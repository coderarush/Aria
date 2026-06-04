import XCTest
@testable import Aria

final class SafetyTests: XCTestCase {
    func testFlagsDestructiveSteps() {
        XCTAssertTrue(Safety.isDestructive(tool: "shell", input: ["command": "rm -rf ~/x"]))
        XCTAssertTrue(Safety.isDestructive(tool: "send_mail", input: ["to": "a@b.com"]))
        XCTAssertFalse(Safety.isDestructive(tool: "open_app", input: ["name": "Spotify"]))
        XCTAssertFalse(Safety.isDestructive(tool: "web_search", input: ["query": "cats"]))
    }

    func testFlagsDestructiveAgentSummaries() {
        XCTAssertTrue(Safety.isDestructive(summary: "send the email to John"))
        XCTAssertTrue(Safety.isDestructive(summary: "delete the old backups"))
        XCTAssertFalse(Safety.isDestructive(summary: "research the best mics"))
    }
}
