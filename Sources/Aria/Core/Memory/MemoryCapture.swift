import Foundation

/// Detects an explicit "remember this" instruction in a command and extracts the
/// fact to store — deterministic, so it costs zero model quota.
enum MemoryCapture {
    private static let triggers = [
        "remember that ", "remember ", "don't forget that ", "don't forget ",
        "keep in mind that ", "keep in mind ", "note that ", "make a note that ",
        "for future reference, ", "fyi, "
    ]

    /// Returns the fact to remember (original casing), or nil if not a remember command.
    static func extract(_ command: String) -> String? {
        let lower = command.lowercased()
        for t in triggers {
            if lower.hasPrefix(t) {
                let fact = String(command.dropFirst(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return fact.isEmpty ? nil : normalizeFirstPerson(fact)
            }
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
