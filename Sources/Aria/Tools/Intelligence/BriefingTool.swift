import Foundation

/// The daily briefing as a tool (V11 P8): lets recipes — and the model —
/// invoke the signature workflow as a step. Same composer as "brief me" and
/// the scheduled agent; the result is the briefing text, which downstream
/// steps (save_note, notify) can chain on.
struct BriefingTool: AriaTool {
    static let name = "daily_briefing"
    static let description = "Compose the user's daily briefing (calendar, reminders, recent work, projects, notes). Use when a workflow needs the briefing as a step; for a spoken 'brief me', the dedicated flow already handles it."

    private let gemini: GeminiClient

    init(gemini: GeminiClient = GeminiClient()) {
        self.gemini = gemini
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let (text, ok) = await BriefingComposer.compose(gemini: gemini)
        return ok ? .ok(text) : .ok(text, diagnostics: "composed from raw inputs (model unreachable)")
    }
}
