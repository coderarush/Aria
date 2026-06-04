import Foundation

/// Owns one continuous conversation: routes finalized user turns to a handler,
/// and ends on dismiss phrases (silence-timeout end is wired by the controller).
@MainActor
final class ConversationSession {
    private let onEnd: () -> Void
    private let onTurn: (String) -> Void
    private(set) var hasEnded = false

    private static let dismissPhrases = ["thanks aria", "that's all", "dismiss", "never mind", "goodbye aria"]

    init(onEnd: @escaping () -> Void, onTurn: @escaping (String) -> Void = { _ in }) {
        self.onEnd = onEnd
        self.onTurn = onTurn
    }

    func start() { hasEnded = false }

    /// A finalized user utterance.
    func userSaid(_ text: String) {
        guard !hasEnded else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if Self.dismissPhrases.contains(where: { t.lowercased().contains($0) }) { end(); return }
        onTurn(t)
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        onEnd()
    }
}
