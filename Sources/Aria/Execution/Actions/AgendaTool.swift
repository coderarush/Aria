import Foundation

/// Builds an optimized day plan from calendar events, reminders, and recent work.
struct AgendaTool: AriaTool {
    static let name = "agenda_plan"
    static let description = "Build an optimized day plan from your calendar events, reminders, and recent work context. Optional input: {create_events} (\"true\"/\"false\", default false — planning only in this version)."
    static let paramHints: [String: String] = [
        "create_events": "Whether to create calendar events for the plan (default false; deferred)"
    ]

    private let gemini: GeminiClient
    private let planner: AgendaPlanner

    init(gemini: GeminiClient = GeminiClient(),
         planner: AgendaPlanner = AgendaPlanner()) {
        self.gemini = gemini
        self.planner = planner
    }

    func run(input: [String: String]) async throws -> ToolResult {
        // Gather context from existing tools
        let calendarEvents = await fetchContext(tool: GcalUpcomingTool(), input: [:])
        let reminders = await fetchContext(tool: RemindersTool(), input: [:])
        let recentWork = await fetchContext(tool: RecallWorkTool(), input: [:])

        let plan = try await planner.plan(
            calendarEvents: calendarEvents,
            reminders: reminders,
            recentWork: recentWork
        ) { prompt in
            try await gemini.generateText(prompt: prompt)
        }

        var lines: [String] = ["Your day plan for \(plan.date):"]
        for item in plan.items {
            lines.append("[\(item.time)] \(item.title) (\(item.durationMinutes)min) — \(item.notes)")
        }
        if !plan.focusSuggestion.isEmpty {
            lines.append("\nFocus suggestion: \(plan.focusSuggestion)")
        }
        if !plan.summary.isEmpty {
            lines.append("\n\(plan.summary)")
        }

        return .ok(lines.joined(separator: "\n"))
    }

    private func fetchContext(tool: some AriaTool, input: [String: String]) async -> String {
        let result = try? await tool.run(input: input)
        return result?.output ?? ""
    }
}
