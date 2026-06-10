import SwiftUI
import Combine

/// State machine + presentation state for the Island pill. Mirrors the old
/// OrbViewModel but with idle/listening/thinking/responding/error states and an
/// accent color for theming.
@MainActor
final class IslandViewModel: ObservableObject {

    enum State: Equatable { case idle, listening, thinking, responding, error }

    @Published private(set) var state: State = .idle
    @Published var responseText: String = ""
    @Published var audioLevel: Float = 0
    @Published var isVisible: Bool = false
    @Published var accent: Color = .accentColor
    @Published var glowColors: [Color] = []
    /// Proactive Presence: a silent "I have a suggestion" glow, independent of
    /// `state` so it can sit on top of any state without disturbing the wake/
    /// listen/think flow. Speaks only when the user reveals it.
    @Published private(set) var hasSuggestion: Bool = false

    /// Fired when the pill wants the hosting panel to show/hide.
    var onVisibilityChange: ((Bool) -> Void)?

    private var dismissTask: Task<Void, Never>?
    var autoDismiss: TimeInterval = 8

    func beginListening() {
        cancelDismiss()
        responseText = ""
        setState(.listening)
        setVisible(true)
    }

    func beginThinking() { cancelDismiss(); setState(.thinking) }

    func showResponse(_ text: String) {
        responseText = text
        setState(.responding)
        scheduleDismiss()
    }

    /// Append streamed text WITHOUT scheduling auto-dismiss — the pill stays
    /// visible through a live conversation (it's dismissed when the session ends).
    func appendResponse(_ delta: String) {
        cancelDismiss()
        if state != .responding { responseText = "" }
        responseText += delta
        setState(.responding)
    }

    func showError(_ text: String = "") {
        responseText = text
        setState(.error)
        scheduleDismiss(after: 3)
    }

    func dismiss() {
        cancelDismiss()
        responseText = ""
        setState(.idle)
        setVisible(false)
    }

    func updateAudioLevel(_ level: Float) { audioLevel = level }

    /// Surface the orb in a silent "I have a suggestion" glow. Makes the panel
    /// visible without entering the listening/thinking flow.
    func showSuggestionGlow() {
        hasSuggestion = true
        setVisible(true)
    }

    /// Clear the glow; hide the orb again if nothing else is showing.
    func clearSuggestionGlow() {
        hasSuggestion = false
        if state == .idle { setVisible(false) }
    }

    private func setState(_ new: State) { guard state != new else { return }; state = new }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        onVisibilityChange?(visible)
    }

    private func scheduleDismiss(after seconds: TimeInterval? = nil) {
        cancelDismiss()
        let delay = seconds ?? autoDismiss
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func cancelDismiss() { dismissTask?.cancel(); dismissTask = nil }
}
