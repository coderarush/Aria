import Foundation

/// Lightweight per-turn routing: pick a fast vs strong model and decide whether
/// the turn needs a screenshot. Heuristic now; can be model-driven later.
enum ModelRouter {
    private static let complexHints = ["analyze", "write a", "plan", "research", "compare",
                                       "debug", "refactor", "summary report", "step by step", "multi"]
    private static let screenHints = ["screen", "this", "here", "what's on", "selected", "highlighted", "see"]

    /// Fast `flash-lite` for chat (low latency + higher free RPM); `pro` for complex.
    static func model(for command: String) -> String {
        let c = command.lowercased()
        return complexHints.contains(where: c.contains) ? "gemini-2.5-pro" : "gemini-2.5-flash-lite"
    }

    /// Fast model for structured, latency-sensitive calls (autonomy planning and
    /// recovery): low latency + higher free RPM, and it keeps `flash` free for the
    /// heavier per-step work so steps wait less on the quota bucket.
    static let fastStructured = "gemini-2.5-flash-lite"

    static func needsScreen(for command: String) -> Bool {
        let c = command.lowercased()
        return screenHints.contains(where: c.contains)
    }
}
