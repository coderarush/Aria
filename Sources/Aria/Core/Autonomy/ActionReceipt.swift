import Foundation

/// The record of one action Aria took — what, when, how consequential, and how to
/// undo it. Every executed step produces one, so the user can always see what she
/// did and reverse the reversible ones. This is the trust core of v11.1.1 autonomy.
struct ActionReceipt: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let summary: String
    let tool: String
    let importance: ActionImportance
    /// Present when the action can be undone; nil for irreversible ones.
    let reversible: ReversibleAction?

    var canUndo: Bool { reversible != nil }

    init(id: UUID = UUID(), summary: String, tool: String, importance: ActionImportance,
         reversible: ReversibleAction?, at: Date) {
        self.id = id
        self.timestamp = at
        self.summary = summary
        self.tool = tool
        self.importance = importance
        self.reversible = reversible
    }
}
