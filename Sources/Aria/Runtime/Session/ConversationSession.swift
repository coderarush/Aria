import Foundation

/// Owns one continuous conversation: routes finalized user turns to a handler,
/// and ends on dismiss phrases (silence-timeout end is wired by the controller).
@MainActor
final class ConversationSession {
    private let onEnd: () -> Void
    private let onTurn: (String) -> Void
    private(set) var hasEnded = false

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
        if DismissIntent.matches(t) { end(); return }
        onTurn(t)
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        onEnd()
    }
}

/// Matches only a complete dismissal utterance. Substring matching here would
/// swallow legitimate requests such as "how do I stop Safari from reloading?".
enum DismissIntent {
    private static let phrases: Set<String> = [
        "dismiss", "thanks aria", "never mind", "bye", "bye aria", "goodbye",
        "goodbye aria", "go away", "okay go away", "thats all", "thats it",
        "you can go", "stop", "get out of here", "see you", "later aria",
    ]

    static func matches(_ text: String) -> Bool {
        let words = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return phrases.contains(words.joined(separator: " "))
    }
}
