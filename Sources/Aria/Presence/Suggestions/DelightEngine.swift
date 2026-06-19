import Foundation

/// A small win, surfaced quietly (spec §111).
struct Delight: Sendable {
    let kind: String
    let message: String
}

/// Produces small wins (spec §111): continued naturally, fewer clicks, context
/// preserved, predicted correctly. Never interrupts, manipulates, or gamifies.
struct DelightEngine: Sendable {
    let interrupts = false
    let manipulates = false
    let gamifies = false

    func note(_ win: String) -> Delight {
        Delight(kind: "win", message: win)
    }
}
