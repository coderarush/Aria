import Foundation

/// Undo the last N reversible actions Aria took. Reads from the `ActionLedger`
/// (newest-first) and calls `undo(id:)` for each reversible receipt, up to the
/// requested count (clamped 1–10).
struct UndoLastNTool: AriaTool {
    static let name = "undo_last_n"
    static let description = "Undo the last N reversible actions Aria took. Input: count (default 1, max 10)."
    static let paramHints: [String: String] = [
        "count": "Number of recent reversible actions to undo (1–10, default 1)"
    ]

    var ledger: ActionLedger

    init(ledger: ActionLedger = ActionLedger.shared) {
        self.ledger = ledger
    }

    func run(input: [String: String]) async throws -> ToolResult {
        // Parse count with default=1, clamped to 1...10
        let raw = input["count"].flatMap { Int($0) } ?? 1
        let count = max(1, min(10, raw))

        // All receipts newest-first, filter to reversible ones
        let allReceipts = await ledger.recent(500)
        let reversible = allReceipts.filter { $0.canUndo }

        guard !reversible.isEmpty else {
            return .ok("Nothing to undo — no recent reversible actions found.")
        }

        let toUndo = Array(reversible.prefix(count))
        var undone: [String] = []

        for receipt in toUndo {
            let result = await ledger.undo(id: receipt.id)
            if result.success {
                undone.append(receipt.summary)
            }
        }

        guard !undone.isEmpty else {
            return .fail("Couldn't undo any actions — they may have already been undone.")
        }

        let lines = undone.map { "• \($0)" }.joined(separator: "\n")
        return .ok("Undid \(undone.count) action\(undone.count == 1 ? "" : "s"):\n\(lines)")
    }
}
