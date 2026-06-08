import XCTest
@testable import Aria

final class SafetyTests: XCTestCase {
    func testFlagsDestructiveSteps() {
        XCTAssertTrue(Safety.isDestructive(tool: "shell", input: ["command": "rm -rf ~/x"]))
        XCTAssertTrue(Safety.isDestructive(tool: "send_mail", input: ["to": "a@b.com"]))
        XCTAssertFalse(Safety.isDestructive(tool: "open_app", input: ["name": "Spotify"]))
        XCTAssertFalse(Safety.isDestructive(tool: "web_search", input: ["query": "cats"]))
    }

    func testSafeToolsNotFlaggedByContent() {
        // Innocent content containing danger words must NOT trip the gate.
        XCTAssertFalse(Safety.isDestructive(tool: "web_search", input: ["query": "how to delete files on mac"]))
        XCTAssertFalse(Safety.isDestructive(tool: "ui_type", input: ["text": "send my regards to the team"]))
        XCTAssertFalse(Safety.isDestructive(tool: "ui_read", input: [:]))
        // But clicking a destructive control IS gated.
        XCTAssertTrue(Safety.isDestructive(tool: "ui_click", input: ["label": "Delete project"]))
    }

    func testEmailToolDestructiveness() {
        XCTAssertTrue(SendMailTool().isDestructive)                              // send → gated
        XCTAssertFalse(EmailDraftTool().isDestructive)                          // draft → prep only
        XCTAssertFalse(Safety.isDestructive(tool: "email_recent", input: [:]))  // read → safe
        XCTAssertFalse(Safety.isDestructive(tool: "email_search", input: ["query": "invoice"]))
    }

    func testFlagsDestructiveAgentSummaries() {
        XCTAssertTrue(Safety.isDestructive(summary: "send the email to John"))
        XCTAssertTrue(Safety.isDestructive(summary: "delete the old backups"))
        XCTAssertFalse(Safety.isDestructive(summary: "research the best mics"))
    }
}
