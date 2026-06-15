import XCTest
@testable import Aria

final class ActionReceiptTests: XCTestCase {
    func testReceiptCarriesUndoForReversible() {
        let r = ActionReceipt(summary: "save notes", tool: "file_write",
                              importance: .reversible,
                              reversible: .fileWrite(path: "~/a.txt", previousContent: nil),
                              at: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(r.canUndo)
        XCTAssertEqual(r.importance, .reversible)
    }
    func testIrreversibleHasNoUndo() {
        let r = ActionReceipt(summary: "email", tool: "send_mail",
                              importance: .importantIrreversible, reversible: nil,
                              at: Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(r.canUndo)
    }
    func testCodableRoundTrip() throws {
        let r = ActionReceipt(summary: "s", tool: "file_write", importance: .reversible,
                              reversible: .clipboardWrite(previous: "x"), at: Date(timeIntervalSince1970: 1))
        let back = try JSONDecoder().decode(ActionReceipt.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.summary, "s")
        XCTAssertEqual(back.canUndo, true)
    }
}
