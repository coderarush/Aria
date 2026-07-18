import Foundation

/// Decides, from the user's command alone, which extra context is actually relevant
/// this turn — so Aria stays "fully aware" while pulling information *intentionally*,
/// only when it bears on the objective (directive: efficient, intentional, explainable),
/// and avoids feeding private data (e.g. the clipboard) into every prompt.
enum ContextRelevance {
    private static let clipboardWords = [
        "clipboard", "copied", "i copied", "what i copied", "paste", "pasted",
        "the copy", "just copied", "on my clipboard", "in my clipboard"
    ]

    /// True when the command refers to the clipboard / something the user copied —
    /// the only time we attach clipboard contents to the turn.
    static func wantsClipboard(_ command: String) -> Bool {
        let c = command.lowercased()
        return clipboardWords.contains { c.contains($0) }
    }
}
