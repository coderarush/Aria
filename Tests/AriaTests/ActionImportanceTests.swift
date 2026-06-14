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
    func testOnlyImportantIrreversibleGates() {
        XCTAssertFalse(ActionImportance.routine.requiresApproval)
        XCTAssertFalse(ActionImportance.reversible.requiresApproval)
        XCTAssertTrue(ActionImportance.importantIrreversible.requiresApproval)
    }
}
