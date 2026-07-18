import SwiftUI
import Combine

/// State machine + presentation state for the Island pill. Mirrors the old
/// OrbViewModel but with idle/listening/thinking/responding/error states and an
/// accent color for theming.
@MainActor
final class IslandViewModel: ObservableObject {

    enum State: Equatable { case idle, listening, thinking, executing, responding, error }

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
    /// System-wide dictation in progress — the caption reads "Dictating…" so the
    /// user knows their words are being typed, not interpreted as a command.
    @Published var isDictating: Bool = false
    @Published private(set) var liquidPhase: LiquidSurfacePhase = .resting
    @Published private(set) var invocationSource: LiquidInvocationSource?
    @Published private(set) var draftText = ""
    @Published private(set) var workLabel = ""
    @Published private(set) var responseHeadline = ""
    @Published private(set) var cue: LiquidCue?

    /// Fired when the pill wants the hosting panel to show/hide.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Lets the active liquid panel collapse while the passive resting blob stays.
    var onSurfaceDismiss: (() -> Void)?

    private var dismissTask: Task<Void, Never>?
    var autoDismiss: TimeInterval = 8

    func beginListening(source: LiquidInvocationSource = .voice) {
        cancelDismiss()
        responseText = ""
        responseHeadline = ""
        draftText = ""
        invocationSource = source
        liquidPhase = .listening
        setState(.listening)
        setVisible(true)
    }

    func beginComposing(source: LiquidInvocationSource = .keyboard) {
        cancelDismiss()
        invocationSource = source
        draftText = ""
        responseText = ""
        responseHeadline = ""
        liquidPhase = .composing
        setState(.idle)
        setVisible(true)
    }

    func updateDraft(_ text: String) { draftText = text }

    /// Speech recognizers revise partials; replacing prevents duplicated words.
    func replacePartialTranscript(_ text: String) {
        draftText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if liquidPhase != .listening { liquidPhase = .listening }
    }

    func beginThinking(workLabel: String = "Thinking…") {
        cancelDismiss(); self.workLabel = workLabel; liquidPhase = .working; setState(.thinking); setVisible(true)
    }

    /// Enter multi-step execution: she splashes to the screen edge and works as
    /// the rotating border. Only the autonomy (plan→execute) path calls this —
    /// simple conversational answers never splash.
    func beginExecuting() { cancelDismiss(); workLabel = "Working…"; liquidPhase = .working; setState(.executing); setVisible(true) }

    func showResponse(_ text: String) {
        responseText = text
        responseHeadline = ResponseHeadline.make(from: text)
        liquidPhase = .answering
        setState(.responding)
        // Answers remain until an explicit dismissal.
    }

    /// Append streamed text WITHOUT scheduling auto-dismiss — the pill stays
    /// visible through a live conversation (it's dismissed when the session ends).
    func appendResponse(_ delta: String) {
        cancelDismiss()
        if state != .responding { responseText = "" }
        responseText += delta
        responseHeadline = ResponseHeadline.make(from: responseText)
        liquidPhase = .answering
        setState(.responding)
    }

    func showError(_ text: String = "") {
        responseText = text
        responseHeadline = ResponseHeadline.make(from: text)
        liquidPhase = .error
        setState(.error)
    }

    func dismiss() {
        cancelDismiss()
        responseText = ""
        responseHeadline = ""
        draftText = ""
        workLabel = ""
        invocationSource = nil
        liquidPhase = .resting
        setState(.idle)
        onSurfaceDismiss?()
        setVisible(AppSettings.shared.idleBlobVisible)
    }

    func showRestingBlob() {
        liquidPhase = .resting
        setState(.idle)
        setVisible(AppSettings.shared.idleBlobVisible)
    }

    func updateAudioLevel(_ level: Float) { audioLevel = level }

    /// Surface the orb in a silent "I have a suggestion" glow. Makes the panel
    /// visible without entering the listening/thinking flow.
    func showSuggestionGlow() {
        hasSuggestion = true
        setVisible(true)
    }

    func showCue(_ cue: LiquidCue) {
        self.cue = cue
        liquidPhase = .ready
        setVisible(true)
    }

    func clearCue() { cue = nil }

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
