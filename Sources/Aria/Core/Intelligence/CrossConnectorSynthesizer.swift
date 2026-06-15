import Foundation

/// Gathers context from ALL connected apps simultaneously using structured
/// concurrency (`async let`), then synthesizes a unified spoken answer.
/// Stateless struct — no stored properties, no actor isolation needed.
struct CrossConnectorSynthesizer: Sendable {

    /// One fetch closure per connector. Each must return "" (never throw) when
    /// the connector is disconnected or the fetch fails — that keeps a single
    /// bad connector from aborting the whole gather.
    struct Sources: Sendable {
        var gmail:  @Sendable (String) async -> String
        var gcal:   @Sendable (String) async -> String
        var notion: @Sendable (String) async -> String
        var drive:  @Sendable (String) async -> String
        var slack:  @Sendable (String) async -> String
        var github: @Sendable (String) async -> String
        var linear: @Sendable (String) async -> String
    }

    /// Fire all 7 source closures concurrently, collect non-empty results, and
    /// synthesize a unified spoken answer by calling `synthesize`. On any error
    /// from `synthesize` (or an empty result), falls back to the raw labeled
    /// snippets. Never throws, never crashes.
    func gather(
        topic: String,
        sources: Sources,
        synthesize: @Sendable (String) async throws -> String
    ) async -> String {
        // Fan-out: all 7 sources run at the same time.
        async let gmailResult  = sources.gmail(topic)
        async let gcalResult   = sources.gcal(topic)
        async let notionResult = sources.notion(topic)
        async let driveResult  = sources.drive(topic)
        async let slackResult  = sources.slack(topic)
        async let githubResult = sources.github(topic)
        async let linearResult = sources.linear(topic)

        let (g, c, n, d, s, gh, li) = await (
            gmailResult, gcalResult, notionResult,
            driveResult, slackResult, githubResult, linearResult
        )

        // Filter out empty/whitespace-only results.
        let labeled: [(label: String, content: String)] = [
            ("Gmail", g), ("Calendar", c), ("Notion", n), ("Drive", d),
            ("Slack", s), ("GitHub", gh), ("Linear", li)
        ].filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !labeled.isEmpty else {
            return "I didn't find anything about '\(topic)' in your connected apps."
        }

        // Build synthesis prompt.
        let snippets = labeled
            .map { "[\($0.label)]: \($0.content)" }
            .joined(separator: "\n\n")

        let prompt = """
            Synthesize the following into a concise spoken summary about "\(topic)".
            Be brief (3-5 sentences), spoken-word style, no markdown, no bullet points.

            \(snippets)
            """

        // Attempt synthesis; fall back to raw snippets on error or empty result.
        do {
            let synthesized = try await synthesize(prompt)
            if synthesized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return labeled.map { "[\($0.label)]: \($0.content)" }.joined(separator: "\n")
            }
            return synthesized
        } catch {
            return labeled.map { "[\($0.label)]: \($0.content)" }.joined(separator: "\n")
        }
    }
}
