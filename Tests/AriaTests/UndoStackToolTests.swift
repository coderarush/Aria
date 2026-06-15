import XCTest
@testable import Aria

final class UndoStackToolTests: XCTestCase {

    // MARK: Helpers

    private func makeLedger() -> ActionLedger {
        ActionLedger(persist: false)
    }

    /// Record a reversible clipboard-write receipt. clipboardWrite is safe
    /// in tests and doesn't require filesystem access or network tokens.
    private func recordReversible(
        _ ledger: ActionLedger,
        summary: String,
        previous: String? = nil
    ) async {
        await ledger.record(ActionReceipt(
            summary: summary,
            tool: "clipboard_write",
            importance: .reversible,
            reversible: .clipboardWrite(previous: previous),
            at: Date()
        ))
    }

    /// Record an irreversible receipt.
    private func recordIrreversible(_ ledger: ActionLedger, summary: String) async {
        await ledger.record(ActionReceipt(
            summary: summary,
            tool: "shell",
            importance: .routine,
            reversible: nil,
            at: Date()
        ))
    }

    // MARK: Tests

    func testUndoSingleAction() async throws {
        let ledger = makeLedger()
        await recordReversible(ledger, summary: "copied code snippet")

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: ["count": "1"])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("copied code snippet"),
                      "Result should mention the undone action; got: \(result.output)")
    }

    func testUndoMultipleActions() async throws {
        let ledger = makeLedger()
        await recordReversible(ledger, summary: "action one")
        await recordReversible(ledger, summary: "action two")
        await recordReversible(ledger, summary: "action three")

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: ["count": "3"])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("3 action"), "Expected 3 undone; got: \(result.output)")
    }

    func testClampsToAvailable() async throws {
        let ledger = makeLedger()
        await recordReversible(ledger, summary: "only action one")
        await recordReversible(ledger, summary: "only action two")

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: ["count": "5"])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("2 action"), "Expected 2 undone; got: \(result.output)")
    }

    func testNothingToUndo() async throws {
        let ledger = makeLedger()
        // Only irreversible actions
        await recordIrreversible(ledger, summary: "ran shell script")

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: [:])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("nothing to undo"),
                      "Expected nothing-to-undo message; got: \(result.output)")
    }

    func testDefaultCountIsOne() async throws {
        let ledger = makeLedger()
        await recordReversible(ledger, summary: "first reversible")
        await recordReversible(ledger, summary: "second reversible")

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: [:])  // no count → default 1

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("1 action"), "Expected only 1 undone; got: \(result.output)")
    }

    func testMaxClampedToTen() async throws {
        let ledger = makeLedger()
        // Record 15 reversible actions
        for i in 1...15 {
            await recordReversible(ledger, summary: "action \(i)")
        }

        let tool = UndoLastNTool(ledger: ledger)
        let result = try await tool.run(input: ["count": "50"])

        XCTAssertTrue(result.success)
        // Should undo at most 10 (the clamp), even though 15 exist
        XCTAssertTrue(result.output.contains("10 action"), "Expected 10 undone; got: \(result.output)")
    }
}
