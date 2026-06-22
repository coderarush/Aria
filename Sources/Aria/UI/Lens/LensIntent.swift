import Foundation

/// Maps a spoken/typed command to a Lens launch — kept deliberately *explicit*
/// (a gesture mode you ask for) so it never hijacks ordinary questions like
/// "what is this error". Pure + testable.
enum LensIntent {
    /// Returns the Lens mode to open, or nil if the command isn't a Lens request.
    static func mode(for command: String) -> LensSession.Mode? {
        let c = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let drawPhrases = [
            "draw on my screen", "draw on the screen", "let me draw on", "annotate my screen",
            "let me draw on my screen", "draw mode"
        ]
        if drawPhrases.contains(where: c.contains) { return .draw }

        let explainPhrases = [
            "circle to explain", "circle mode", "start lens", "open lens", "lens mode",
            "let me circle", "i'll circle", "i want to circle", "explain what i circle",
            "circle something", "let me show you something on my screen",
            "circle this for me", "explain what i'm pointing at"
        ]
        if explainPhrases.contains(where: c.contains) { return .explain }

        return nil
    }
}
