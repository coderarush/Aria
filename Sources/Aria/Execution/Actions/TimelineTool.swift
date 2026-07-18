import Foundation

/// "What did I do today?" / "Show my week" — the Aria Timeline as a tool
/// (V11 P6). Single days read as a chronological list; multi-day windows
/// read as a per-day rollup with counts.
struct TimelineTool: AriaTool {
    static let name = "timeline"
    static let description = "Show what the user accomplished — a merged timeline of tasks, background agent runs, and actions Aria took. Input: {timeframe: today|yesterday|this week|last week}. Use when the user asks what they did, what happened, or what they accomplished over a period."
    static let paramHints: [String: String] = [
        "timeframe": "today, yesterday, this week, or last week"
    ]

    private let timeline: Timeline
    private let now: () -> Date

    init(timeline: Timeline = Timeline(), now: @escaping () -> Date = Date.init) {
        self.timeline = timeline
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let timeframe = (input["timeframe"] ?? "today").lowercased()
        guard let (from, to, label) = RecallWorkTool.window(for: timeframe, now: now()) else {
            return .fail("Unknown timeframe “\(timeframe)” — use today, yesterday, this week, or last week.")
        }
        let multiDay = timeframe.contains("week")
        if multiDay {
            let rollup = await timeline.dayRollup(from: from, to: to)
            guard !rollup.isEmpty else { return .ok("Nothing on the timeline for \(label).") }
            return .ok("Timeline \(label):\n\(rollup)")
        }
        let events = await timeline.events(from: from, to: to)
        guard !events.isEmpty else { return .ok("Nothing on the timeline for \(label).") }
        let lines = events.suffix(20).map { e in
            let time = e.date.formatted(date: .omitted, time: .shortened)
            let tag = e.project.map { " [\($0)]" } ?? ""
            return "\(e.ok ? "✓" : "✗") \(time) \(e.title)\(tag)"
        }.joined(separator: "\n")
        return .ok("Timeline \(label):\n\(lines)")
    }
}
