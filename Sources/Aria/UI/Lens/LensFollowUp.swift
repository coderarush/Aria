import CoreGraphics
import Foundation

/// What Aria last read out of a circled region — kept briefly so a follow-up like
/// "translate that" or "fix this error" can act on it without re-circling.
struct LensCapture: Equatable {
    let text: String
    let at: Date
}

/// Remembers the most recently circled (Lens) content + region so a deictic
/// follow-up can resolve "this"/"that" to it. Single shared instance; main-actor
/// since the Lens flow and command handling both touch it on the main actor.
@MainActor
final class LensMemory {
    static let shared = LensMemory()
    private(set) var last: LensCapture?
    /// The normalized (0…1) region that was circled, for "watch this".
    private(set) var lastFraction: CGRect?

    func record(text: String, fraction: CGRect? = nil, at: Date = Date()) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        last = t.isEmpty ? nil : LensCapture(text: t, at: at)
        if let fraction { lastFraction = fraction }
    }

    /// The just-circled region if still fresh — used by "watch this" to know
    /// which region to poll.
    func freshFraction(within: TimeInterval = 120, now: Date = Date()) -> CGRect? {
        guard let cap = last, let f = lastFraction, now.timeIntervalSince(cap.at) <= within else { return nil }
        return f
    }

    func clear() { last = nil }
}

/// Folds just-circled content into a follow-up command. Pure + testable. The Lens
/// explains what you circled; this lets the very next thing you say *act* on it —
/// "circle a French paragraph → 'translate that'", "circle an error → 'how do I
/// fix this'". Conservative: only fires when the command actually points back at
/// the circled thing (a deictic word) and the capture is still fresh.
enum LensFollowUp {
    static let freshness: TimeInterval = 120
    static let deictics = ["this", "that", "it", "these", "those", "circled", "highlighted", "selection"]

    /// Returns `command` augmented with the circled content when the command is a
    /// fresh deictic reference to it; otherwise nil (leave the command untouched).
    static func fold(command: String, capture: LensCapture?, now: Date = Date()) -> String? {
        guard let cap = capture, !cap.text.isEmpty,
              now.timeIntervalSince(cap.at) >= 0,
              now.timeIntervalSince(cap.at) <= freshness else { return nil }
        guard deictics.contains(where: { containsWord(command, $0) }) else { return nil }
        let snippet = String(cap.text.prefix(800))
        return """
        \(command)

        [Context — the user just circled this on their screen:
        \"\"\"
        \(snippet)
        \"\"\"]
        """
    }

    /// Whole-word, case-insensitive membership so "it" doesn't match "item" and
    /// "this" doesn't match "thistle".
    static func containsWord(_ text: String, _ word: String) -> Bool {
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        return tokens.contains(word.lowercased())
    }
}
