import Foundation

/// How consequential an action is — the basis for Aria's "act freely unless it
/// really matters" autonomy (v11.1.1). Only `.importantIrreversible` ever pauses
/// for the user; everything else runs and is recorded with an undo receipt.
enum ActionImportance: String, Sendable, Equatable, Codable {
    case routine               // reads, searches, navigation — no state change
    case reversible            // changes state, but Aria can undo it (file/clipboard/…)
    case importantIrreversible // money, delete-with-no-undo, external comms, credentials

    var requiresApproval: Bool { self == .importantIrreversible }
}
