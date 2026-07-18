import Foundation
import AppKit

/// A reversible action Aria performed, with enough captured state to undo it.
/// The directive asks for rollback "wherever technically possible" — we record the
/// few cleanly-reversible built-in actions so the user can say "undo that".
enum ReversibleAction: Sendable, Equatable, Codable {
    /// A file_write. `previousContent == nil` means the file did not exist before
    /// (undo deletes it); otherwise undo restores the prior bytes.
    case fileWrite(path: String, previousContent: String?)
    /// A clipboard write; undo restores the prior string (nil = was empty).
    case clipboardWrite(previous: String?)
    /// A Gmail draft was created in the connected Google account; undo deletes
    /// the draft. `id` is the server-assigned draft id.
    case gmailDraftCreated(id: String)
    /// A Google Calendar event was created on the primary calendar; undo deletes
    /// the event. `id` is the server-assigned event id.
    case calendarEventCreated(id: String)

    /// Short human label for narration / an activity view.
    var label: String {
        switch self {
        case .fileWrite(let path, let previous):
            let name = (path as NSString).lastPathComponent
            return previous == nil ? "creating \(name)" : "overwriting \(name)"
        case .clipboardWrite:
            return "changing the clipboard"
        case .gmailDraftCreated:
            return "creating the Gmail draft"
        case .calendarEventCreated:
            return "adding the calendar event"
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
    /// The most recently recorded reversible action (for attaching to a receipt).
    func lastRecorded() -> ReversibleAction? { actions.last }

    /// Undo the most recent reversible action, or report there's nothing to undo.
    func undoLast() async -> ToolResult {
        guard let action = actions.popLast() else { return .fail("Nothing to undo.") }
        return await UndoStack.revert(action)
    }

    /// Resolves a valid Google access token for the connector-backed reverts.
    /// Defaults to the shared ConnectorStore; tests inject a stub so the no-token
    /// path can be exercised without touching the Keychain or the network.
    typealias GoogleTokenProvider = @Sendable () async -> String?

    /// Perform the inverse of an action. The filesystem / pasteboard cases are
    /// fully self-contained; the connector-backed cases (Gmail draft / Calendar
    /// event) resolve a token via `googleToken` — injectable for tests.
    static func revert(
        _ action: ReversibleAction,
        googleToken: GoogleTokenProvider = { await ConnectorStore.shared.validAccessToken(.google) }
    ) async -> ToolResult {
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

        case .gmailDraftCreated(let id):
            guard let token = await googleToken() else {
                return .fail("Couldn't undo the Gmail draft — reconnect Google in Settings → Connectors → Google, then try again.")
            }
            do {
                try await GoogleConnector().deleteDraft(id: id, accessToken: token)
                return .ok("Deleted the Gmail draft.")
            } catch {
                return .fail("Couldn't delete the Gmail draft — your Google connection may need to be re-authorized in Settings → Connectors → Google.")
            }

        case .calendarEventCreated(let id):
            guard let token = await googleToken() else {
                return .fail("Couldn't undo the calendar event — reconnect Google in Settings → Connectors → Google, then try again.")
            }
            do {
                try await GoogleConnector().deleteEvent(id: id, accessToken: token)
                return .ok("Removed the Google Calendar event.")
            } catch {
                return .fail("Couldn't delete the calendar event — your Google connection may need to be re-authorized in Settings → Connectors → Google.")
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
