import Foundation

/// Whether Aria pauses to confirm before a genuinely destructive action
/// (send / pay / delete / external comms / raw shell). The orchestrator already
/// filters which actions reach the confirmation handler — this just decides
/// whether that handler asks the user or silently approves.
///
/// Safe by default: confirmation is ON unless explicitly turned off. Users who
/// prefer the original zero-friction mode can opt out by setting
/// `app.confirmDestructive` to false. Important irreversible actions remain
/// blocked when no user is present, and not every action can be undone.
enum ConfirmationPolicy {
    static let key = "app.confirmDestructive"

    static func confirmsDestructive(_ defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? true
    }

    /// What to do when an important-irreversible action reaches the handler.
    enum ConfirmDecision { case autoApprove, decline, prompt }

    /// Decide without touching UI, so it's testable. Order matters:
    /// - unattended        → decline (an important-irreversible action must not
    ///                        auto-fire with nobody present)
    /// - confirmation off  → auto-approve an attended power-user request
    /// - already confirming → decline (don't stack modals re-entrantly)
    /// - otherwise         → prompt the user
    static func decision(confirmsDestructive: Bool,
                         unattended: Bool,
                         alreadyConfirming: Bool) -> ConfirmDecision {
        if unattended { return .decline }
        guard confirmsDestructive else { return .autoApprove }
        if alreadyConfirming { return .decline }
        return .prompt
    }
}
