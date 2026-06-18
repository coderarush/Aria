import XCTest
@testable import Aria

final class ActionImportanceTests: XCTestCase {
    func testReadIsRoutine() {
        XCTAssertEqual(Safety.importance(tool: "ui_read", input: [:], summary: "read the screen"), .routine)
    }
    func testFileWriteIsReversible() {
        XCTAssertEqual(Safety.importance(tool: "file_write", input: ["path": "~/a.txt"], summary: "save notes"), .reversible)
    }
    func testSendMailIsImportantIrreversible() {
        XCTAssertEqual(Safety.importance(tool: "send_mail", input: [:], summary: "email the client"), .importantIrreversible)
    }
    func testDeleteIsImportantIrreversible() {
        XCTAssertEqual(Safety.importance(tool: "delete_file", input: [:], summary: "delete the folder"), .importantIrreversible)
    }
    // Regression: a reversible tool whose content/summary contains a danger word
    // ("send") must stay .reversible and NOT trigger a spurious approval prompt.
    func testReversibleToolWithDangerWordInSummaryStaysReversible() {
        XCTAssertEqual(
            Safety.importance(tool: "file_write",
                              input: ["path": "~/notes.txt", "content": "remember to send the invoice"],
                              summary: "file_write: path=~/notes.txt, content=remember to send the invoice"),
            .reversible)
        XCTAssertEqual(
            Safety.importance(tool: "save_note",
                              input: ["content": "delete the old draft and email Bob"],
                              summary: "save_note: content=delete the old draft and email Bob"),
            .reversible)
    }
    func testOnlyImportantIrreversibleGates() {
        XCTAssertFalse(ActionImportance.routine.requiresApproval)
        XCTAssertFalse(ActionImportance.reversible.requiresApproval)
        XCTAssertTrue(ActionImportance.importantIrreversible.requiresApproval)
    }
}
