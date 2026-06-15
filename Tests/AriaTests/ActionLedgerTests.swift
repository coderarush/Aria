import XCTest
@testable import Aria

final class ActionLedgerTests: XCTestCase {
    func testRecordsAndListsNewestFirst() async {
        let ledger = ActionLedger(persist: false)
        await ledger.record(ActionReceipt(summary: "a", tool: "file_write", importance: .reversible,
                                          reversible: .clipboardWrite(previous: nil), at: Date(timeIntervalSince1970: 1)))
        await ledger.record(ActionReceipt(summary: "b", tool: "ui_read", importance: .routine,
                                          reversible: nil, at: Date(timeIntervalSince1970: 2)))
        let recent = await ledger.recent(10)
        XCTAssertEqual(recent.map(\.summary), ["b", "a"])
    }

    func testUndoByIdReversesAndRemoves() async {
        let ledger = ActionLedger(persist: false)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("led-\(UUID()).txt").path
        try? "new".write(toFile: tmp, atomically: true, encoding: .utf8)
        let r = ActionReceipt(summary: "wrote", tool: "file_write", importance: .reversible,
                              reversible: .fileWrite(path: tmp, previousContent: nil), at: Date())
        await ledger.record(r)
        let result = await ledger.undo(id: r.id)
        XCTAssertTrue(result.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp))   // undo deleted the new file
        let undoneAgain = await ledger.undo(id: r.id)
        XCTAssertFalse(undoneAgain.success)                           // already undone → gone from ledger
    }
}
