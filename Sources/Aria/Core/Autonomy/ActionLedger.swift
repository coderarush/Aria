import Foundation

/// The append-only record of every action Aria takes, with undo-by-id for the
/// reversible ones. Wraps `UndoStack.revert` for the actual inverse. Persisted to
/// Application Support so receipts survive relaunch (the activity / receipts UI
/// reads it). This is what makes high autonomy safe: nothing happens unseen, and
/// anything reversible can be taken back.
actor ActionLedger {
    static let shared = ActionLedger()

    private var receipts: [ActionReceipt] = []
    private let cap = 500
    private let url: URL?

    init(persist: Bool = true) {
        url = persist ? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("action-receipts.json") : nil
        if let url, let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([ActionReceipt].self, from: data) {
            receipts = loaded
        }
    }

    func record(_ r: ActionReceipt) {
        receipts.append(r)
        if receipts.count > cap { receipts.removeFirst(receipts.count - cap) }
        save()
    }

    /// Most recent first.
    func recent(_ limit: Int) -> [ActionReceipt] {
        Array(receipts.suffix(limit).reversed())
    }

    /// Undo a specific receipt by id (reverses it + drops it from the ledger).
    func undo(id: UUID) async -> ToolResult {
        guard let idx = receipts.firstIndex(where: { $0.id == id }),
              let action = receipts[idx].reversible else { return .fail("Nothing to undo.") }
        let result = await UndoStack.revert(action)
        if result.success { receipts.remove(at: idx); save() }
        return result
    }

    /// The most recent still-undoable receipt, if any (for "undo that").
    func latestUndoable() -> ActionReceipt? {
        receipts.last { $0.canUndo }
    }

    private func save() {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(receipts) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
