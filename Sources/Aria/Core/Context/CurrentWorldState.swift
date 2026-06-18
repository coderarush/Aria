import Foundation

/// One canonical snapshot of "what is happening right now" — the union of the
/// ambient signals Aria already tracks, gathered into a single value the model
/// (and the intent engine) can reason over cohesively.
///
/// This is a grouping value type, NOT a new source of truth: every field is read
/// from an existing engine (AppFocusMonitor, ClipboardContext, WorkJournal, …).
/// `activeWindow` is reserved for a future AX window-title read; it is nil today.
struct CurrentWorldState: Sendable, Equatable, Codable {
    var activeApp: String
    var activeWindow: String?
    var focusDuration: TimeInterval
    var clipboardSummary: String?
    var openFiles: [String]
    var recentActions: [String]
    var pendingSuggestion: String?
    /// How complete the picture is right now: the fraction of the four core
    /// signals (app / clipboard / files / recent actions) currently populated.
    var confidence: Double
    var timestamp: Date

    /// Build a snapshot from already-gathered source values. Pure and testable —
    /// the actor does the I/O, this does the assembly + derived fields.
    static func build(activeApp: String,
                      focusSince: Date?,
                      clipboardSummary: String?,
                      openFiles: [String],
                      recentActions: [String],
                      pendingSuggestion: String?,
                      now: Date) -> CurrentWorldState {
        let duration = focusSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        var present = 0.0
        if !activeApp.isEmpty { present += 1 }
        if clipboardSummary?.isEmpty == false { present += 1 }
        if !openFiles.isEmpty { present += 1 }
        if !recentActions.isEmpty { present += 1 }
        return CurrentWorldState(
            activeApp: activeApp,
            activeWindow: nil,
            focusDuration: duration,
            clipboardSummary: clipboardSummary,
            openFiles: openFiles,
            recentActions: recentActions,
            pendingSuggestion: pendingSuggestion,
            confidence: present / 4.0,
            timestamp: now)
    }
}
