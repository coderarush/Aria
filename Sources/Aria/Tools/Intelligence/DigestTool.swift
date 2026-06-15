import Foundation

/// "Aria, give me my daily digest" — assembles today's activity timeline,
/// overdue follow-ups, and tomorrow's calendar, then feeds them through
/// `DigestEngine` to produce a structured end-of-day summary.
struct DigestTool: AriaTool {
    static let name = "digest"
    static let description = "Generate a daily digest — a structured end-of-day summary of accomplishments, overdue items, and tomorrow's preview. Input: none."

    private let engine: DigestEngine
    private let gemini: GeminiClient

    init(engine: DigestEngine = DigestEngine(), gemini: GeminiClient = GeminiClient()) {
        self.engine = engine
        self.gemini = gemini
    }

    func run(input: [String: String]) async throws -> ToolResult {
        // Gather context from the underlying engines directly
        let timelineResult = try await TimelineTool().run(input: ["timeframe": "today"])
        let followUpResult = try await FollowUpTool().run(input: [:])
        let calResult = try await GcalUpcomingTool().run(input: [:])

        let timeline = timelineResult.output
        let followUps = followUpResult.output
        let tomorrowCalendar = calResult.output

        let digest = await engine.generate(
            timeline: timeline,
            followUps: followUps,
            tomorrowCalendar: tomorrowCalendar,
            synthesize: { prompt in try await gemini.generateText(prompt: prompt) }
        )

        let output = format(digest)
        return .ok(output)
    }

    private func format(_ digest: DailyDigest) -> String {
        var parts: [String] = []
        parts.append("📅 Daily Digest — \(digest.date)")
        parts.append("")
        parts.append(digest.summary)
        parts.append("")
        parts.append("✅ Accomplishments:")
        if digest.accomplishments.isEmpty {
            parts.append("• Nothing logged yet today.")
        } else {
            parts.append(contentsOf: digest.accomplishments.map { "• \($0)" })
        }
        parts.append("")
        parts.append("⚠️ Overdue:")
        if digest.overdueItems.isEmpty {
            parts.append("All caught up!")
        } else {
            parts.append(contentsOf: digest.overdueItems.map { "• \($0)" })
        }
        parts.append("")
        parts.append("📆 Tomorrow:")
        parts.append(digest.tomorrowPreview)
        return parts.joined(separator: "\n")
    }
}
