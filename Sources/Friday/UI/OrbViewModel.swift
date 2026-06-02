import SwiftUI
import Combine

/// State machine + presentation state for the orb. Drives transitions between
/// hidden / listening / thinking / acting / responding / error and owns the
/// auto-dismiss timer.
@MainActor
final class OrbViewModel: ObservableObject {

    enum State: Equatable {
        case hidden
        case listening
        case thinking
        case acting        // sub-agents running (visual reserved for later)
        case responding
        case error
    }

    @Published private(set) var state: State = .hidden
    @Published var responseText: String = ""
    @Published var audioLevel: Float = 0
    @Published var isVisible: Bool = false

    /// Fired when the orb wants the hosting panel to show/hide.
    var onVisibilityChange: ((Bool) -> Void)?

    private var dismissTask: Task<Void, Never>?
    private let autoDismiss: TimeInterval = 8

    // MARK: Transitions

    func beginListening() {
        cancelDismiss()
        responseText = ""
        setState(.listening)
        setVisible(true)
    }

    func beginThinking() {
        cancelDismiss()
        setState(.thinking)
    }

    func beginActing() {
        cancelDismiss()
        setState(.acting)
    }

    func showResponse(_ text: String) {
        responseText = text
        setState(.responding)
        scheduleDismiss()
    }

    func showError(_ text: String = "") {
        responseText = text
        setState(.error)
        scheduleDismiss(after: 3)
    }

    func dismiss() {
        cancelDismiss()
        setState(.hidden)
        setVisible(false)
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = level
    }

    // MARK: Helpers

    private func setState(_ new: State) {
        guard state != new else { return }
        state = new
    }

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

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
