import Foundation

/// Decides when Aria should ACT on her own anticipation rather than just offer it
/// (v11.1.1 Phase D). She only auto-acts when it's clearly safe: the user opted in,
/// confidence is very high, the action is a runnable command, and that command is
/// reversible/routine — never something important-irreversible (send/delete/pay),
/// which always surfaces to ask. Everything she does auto-fire is receipted and
/// undoable, so a wrong guess is one "undo" away.
enum AnticipationPolicy {
    /// Default confidence a suggestion must clear to act unprompted.
    static let autoActFloor = 0.9

    /// The command to run on Aria's own initiative, or nil if she should instead
    /// surface the suggestion and wait.
    static func autoActCommand(for s: Suggestion, enabled: Bool,
                               confidenceFloor: Double = autoActFloor) -> String? {
        guard enabled, s.confidence >= confidenceFloor else { return nil }
        guard case .runCommand(let cmd) = s.action else { return nil }
        // Reversible/routine only — important-irreversible always asks first.
        guard !Safety.isDestructive(summary: cmd) else { return nil }
        return cmd
    }
}
