import Foundation

/// The side-effecting surface a presenter drives. Kept behind a protocol so the
/// presenter's decision logic is testable without AppKit, voice, or the
/// orchestrator. The live implementation lives in `AriaController`.
@MainActor
protocol PresenterSurface: AnyObject {
    /// Put the orb into the silent "I have something" glow.
    func showGlow()
    /// Return the orb to its resting state.
    func clearGlow()
    /// Speak the one-line offer aloud.
    func speak(_ line: String)
    /// Run an accepted natural-language command.
    func runCommand(_ command: String) async
    /// Approve an accepted learned automation.
    func approvePattern(_ id: UUID) async
}

/// Drives a single pending suggestion through the silent-glow → reveal → resolve
/// lifecycle. Surfacing never blocks: the orb glows silently until the user
/// glances (reveal) or it expires.
@MainActor
final class SuggestionPresenter {

    private let surface: PresenterSurface
    private let onOutcome: (SuggestionOutcome, Suggestion) -> Void

    private(set) var pending: Suggestion?
    private var revealed = false

    init(surface: PresenterSurface,
         onOutcome: @escaping (SuggestionOutcome, Suggestion) -> Void) {
        self.surface = surface
        self.onOutcome = onOutcome
    }

    /// Begin surfacing: silent glow, nothing spoken yet.
    func present(_ suggestion: Suggestion) {
        pending = suggestion
        revealed = false
        surface.showGlow()
    }

    /// User glanced/woke Aria — speak the offer (once).
    func reveal() {
        guard let s = pending, !revealed else { return }
        revealed = true
        surface.speak(s.spokenLine)
    }

    /// User accepted — run the action and resolve.
    func accept(now: Date) async {
        guard let s = pending else { return }
        switch s.action {
        case .runCommand(let cmd): await surface.runCommand(cmd)
        case .offerAutomation(let id): await surface.approvePattern(id)
        case .acknowledge: break
        }
        onOutcome(.accepted, s)
        clear()
    }

    /// User declined (or said nothing in the accept window).
    func dismiss(now: Date) {
        guard let s = pending else { return }
        onOutcome(.dismissed, s)
        clear()
    }

    /// Untouched past its expiry — clear silently.
    func expire(now: Date) {
        guard let s = pending else { return }
        onOutcome(.expired, s)
        clear()
    }

    private func clear() {
        pending = nil
        revealed = false
        surface.clearGlow()
    }
}
