import Foundation
import AppKit

/// A reversible action Aria performed, with enough captured state to undo it.
/// The directive asks for rollback "wherever technically possible" — we record the
/// few cleanly-reversible built-in actions so the user can say "undo that".
enum ReversibleAction: Sendable, Equatable {
    /// A file_write. `previousContent == nil` means the file did not exist before
    /// (undo deletes it); otherwise undo restores the prior bytes.
    case fileWrite(path: String, previousContent: String?)
    /// A clipboard write; undo restores the prior string (nil = was empty).
    case clipboardWrite(previous: String?)

    /// Short human label for narration / an activity view.
    var label: String {
        switch self {
        case .fileWrite(let path, let previous):
            let name = (path as NSString).lastPathComponent
            return previous == nil ? "creating \(name)" : "overwriting \(name)"
        case .clipboardWrite:
            return "changing the clipboard"
        }
    }
}

/// LIFO stack of reversible actions. An actor — the execution chokepoint records
/// from concurrent tasks. Capped so it can't grow without bound.
actor UndoStack {
    static let shared = UndoStack()

    private var actions: [ReversibleAction] = []
    private let cap: Int

    init(cap: Int = 50) { self.cap = cap }

    func record(_ action: ReversibleAction) {
        actions.append(action)
        if actions.count > cap { actions.removeFirst(actions.count - cap) }
    }

    var canUndo: Bool { !actions.isEmpty }
    func peekLabel() -> String? { actions.last?.label }
    func depth() -> Int { actions.count }

    /// Undo the most recent reversible action, or report there's nothing to undo.
    func undoLast() async -> ToolResult {
        guard let action = actions.popLast() else { return .fail("Nothing to undo.") }
        return await UndoStack.revert(action)
    }

    /// Perform the inverse of an action. Pure-ish (filesystem / pasteboard only) so
    /// it's unit-testable in isolation.
    static func revert(_ action: ReversibleAction) async -> ToolResult {
        switch action {
        case .fileWrite(let path, let previous):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            do {
                if let previous {
                    try previous.write(to: url, atomically: true, encoding: .utf8)
                    return .ok("Restored the previous contents of \(url.lastPathComponent).")
                } else {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    return .ok("Removed \(url.lastPathComponent) — it didn't exist before.")
                }
            } catch {
                return .fail("Couldn't undo the file write: \(error.localizedDescription)")
            }

        case .clipboardWrite(let previous):
            return await MainActor.run {
                let pb = NSPasteboard.general
                pb.clearContents()
                if let previous { pb.setString(previous, forType: .string) }
                return .ok("Restored the previous clipboard contents.")
            }
        }
    }
}

/// Undo Aria's last reversible action — exposed as a tool so the user/model can
/// invoke it ("undo that").
struct UndoTool: AriaTool {
    static let name = "undo"
    static let description = "Undo Aria's last reversible action (a file write or clipboard change). Input: none."
    static let paramHints: [String: String] = [:]

    func run(input: [String: String]) async throws -> ToolResult {
        await UndoStack.shared.undoLast()
    }
}
