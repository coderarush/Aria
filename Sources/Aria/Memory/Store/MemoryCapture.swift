import Foundation

/// Detects an explicit "remember this" instruction in a command and extracts the
/// fact to store — deterministic, so it costs zero model quota.
enum MemoryCapture {
    private static let triggers = [
        "remember that ", "remember ", "don't forget that ", "don't forget ",
        "keep in mind that ", "keep in mind ", "note that ", "make a note that ",
        "for future reference, ", "fyi, "
    ]

    /// Words that make "remember …" a QUESTION/recall or a task, not a fact to store.
    private static let notAFact = ["when", "if", "how", "what", "where", "who", "why",
                                   "whether", "to ", "the time", "that time"]

    /// Returns the fact to remember (original casing), or nil if not a "store this" command.
    static func extract(_ command: String) -> String? {
        let lower = command.lowercased()
        // A question ("remember when we…?") is recall, not storage.
        if lower.hasSuffix("?") { return nil }
        for t in triggers where lower.hasPrefix(t) {
            let rest = String(command.dropFirst(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { return nil }
            let restLower = rest.lowercased()
            if Self.notAFact.contains(where: { restLower.hasPrefix($0) }) { return nil }
            return normalizeFirstPerson(rest)
        }
        return nil
    }

    /// "my name is Sam" → "my name is Sam" (kept first-person, as the user said it);
    /// trims a trailing period for tidiness.
    private static func normalizeFirstPerson(_ s: String) -> String {
        var f = s
        if f.hasSuffix(".") { f.removeLast() }
        return f
    }
}
