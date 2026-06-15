import Foundation

/// Composes a spoken pre-meeting context brief by pulling recent Gmail, Notion,
/// and Drive context concurrently, then synthesizing with a language model.
/// Designed as a plain `struct` (no actor) — all async work is in `brief()`.
struct MeetingBriefEngine: Sendable {

    /// Injectable connector closures. Each takes the event title (as a search
    /// query) and returns a short snippet, or empty string on failure/no result.
    struct ConnectorTools: Sendable {
        var gmailRecent: @Sendable (String) async -> String
        var notionSearch: @Sendable (String) async -> String
        var driveSearch: @Sendable (String) async -> String
    }

    /// Produce a spoken 3-sentence meeting brief.
    ///
    /// - Parameters:
    ///   - eventTitle: Calendar event name — used as the connector search query.
    ///   - attendees: Names or emails of meeting participants.
    ///   - connectorTools: Async closures for Gmail, Notion, and Drive lookups.
    ///   - synthesize: Closure that calls the language model. Accepts the
    ///     assembled prompt string and returns synthesized text. Defaults to
    ///     nil; callers in production pass `{ try await gemini.generateText(prompt: $0, temperature: 0.3) }`.
    ///     Tests pass a stub.
    func brief(
        for eventTitle: String,
        attendees: [String],
        connectorTools: ConnectorTools,
        synthesize: @Sendable (String) async throws -> String
    ) async -> String {

        // 1. Run all 3 connectors concurrently.
        async let gmailResult = connectorTools.gmailRecent(eventTitle)
        async let notionResult = connectorTools.notionSearch(eventTitle)
        async let driveResult = connectorTools.driveSearch(eventTitle)

        let gmail = await gmailResult
        let notion = await notionResult
        let drive = await driveResult

        // 2. Collect non-empty results with source labels.
        var contextParts: [String] = []
        if !gmail.isEmpty  { contextParts.append("Gmail: \(gmail)") }
        if !notion.isEmpty { contextParts.append("Notion: \(notion)") }
        if !drive.isEmpty  { contextParts.append("Drive: \(drive)") }

        // 3. If no connector returned anything, skip synthesis and return fallback.
        guard !contextParts.isEmpty else {
            return fallback(for: eventTitle, attendees: attendees)
        }

        // 4. Build the synthesis prompt.
        let attendeeList = attendees.isEmpty ? "none" : attendees.joined(separator: ", ")
        let contextBlock = contextParts.joined(separator: "\n")
        let prompt = """
        You are Aria. Give a 3-sentence spoken meeting brief for '\(eventTitle)' starting soon. \
        Attendees: \(attendeeList). \
        \(contextBlock). \
        Be concise, spoken-word friendly, no markdown.
        """

        // 5. Call the synthesizer; fall back gracefully on any error or empty result.
        do {
            let result = try await synthesize(prompt)
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback(for: eventTitle, attendees: attendees)
                : result
        } catch {
            return fallback(for: eventTitle, attendees: attendees)
        }
    }

    // MARK: - Private helpers

    private func fallback(for eventTitle: String, attendees: [String]) -> String {
        let attendeePart = attendees.isEmpty
            ? ""
            : " Attendees: \(attendees.joined(separator: ", "))."
        return "Your \(eventTitle) is starting soon.\(attendeePart)"
    }
}
