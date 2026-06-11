import Foundation

/// Lightweight per-turn routing: pick a fast vs strong model and decide whether
/// the turn needs a screenshot. Heuristic now; can be model-driven later.
enum ModelRouter {
    private static let complexHints = ["analyze", "write a", "plan", "research", "compare",
                                       "debug", "refactor", "summary report", "step by step", "multi"]
    // Only EXPLICIT requests to look at the whole screen eager-capture a screenshot.
    // Ambiguous deixis ("this", "here", "see") and text selection ("selected",
    // "highlighted") are covered by ambient AX context (focused window + selected
    // text fed each turn); when the model genuinely needs to *see*, it calls the
    // `look_at_screen` tool. Keeps the common path fast — no redundant vision round.
    // V11 P10: naming a VISUAL artifact ("this chart") is an explicit ask too —
    // AX text can't convey a chart, so those turns eager-capture as well.
    private static let screenHints = ["screen", "what's on", "what is on",
                                      "this chart", "this graph", "this diagram",
                                      "this dashboard", "this image", "this photo",
                                      "this figure", "this design", "this video",
                                      "what am i looking at", "look at this"]

    // V11 P11: bare deixis — the user says "this" without naming anything
    // visual. Selection (ambient AX) answers it when text is selected; when
    // nothing is selected, the turn attaches a late screenshot so "explain
    // this" over a PDF page or a build error just works.
    private static let deixisHints = ["explain this", "summarize this", "what is this",
                                      "what does this mean", "translate this",
                                      "read this", "continue this", "fix this",
                                      "what's this", "analyze this"]

    /// True for commands that point at something ("…this") without naming a
    /// visual artifact — resolve via selection first, screenshot as fallback.
    static func bareDeixis(_ command: String) -> Bool {
        let c = command.lowercased()
        return deixisHints.contains(where: c.contains)
    }

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
