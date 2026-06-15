import Foundation

struct AgendaItem: Codable, Sendable, Equatable {
    var time: String
    var title: String
    var type: String          // "meeting" | "focus" | "task" | "break"
    var durationMinutes: Int
    var notes: String
}

struct DayPlan: Codable, Sendable {
    var date: String
    var items: [AgendaItem]
    var focusSuggestion: String
    var summary: String
}

struct AgendaPlanner: Sendable {
    func plan(
        calendarEvents: String,
        reminders: String,
        recentWork: String,
        synthesize: @Sendable (String) async throws -> String
    ) async throws -> DayPlan {
        let prompt = """
You are a day planner. Create an optimal schedule for today.
Include: fixed meetings (from calendar), suggested focus blocks, task time, breaks.
Return ONLY JSON:
{"date":"today","items":[{"time":"...","title":"...","type":"meeting|focus|task|break","durationMinutes":N,"notes":"..."}],"focusSuggestion":"...","summary":"2-3 sentences"}

Calendar today: \(calendarEvents)
Pending tasks/reminders: \(reminders)
Recent work: \(recentWork)
"""
        let raw: String
        do {
            raw = try await synthesize(prompt)
        } catch {
            return DayPlan(date: "today", items: [], focusSuggestion: "",
                           summary: "Could not generate plan. Here's your raw context: \(calendarEvents)")
        }

        // Find JSON object in the response
        guard let startIdx = raw.firstIndex(of: "{"),
              let endIdx = raw.lastIndex(of: "}"),
              startIdx <= endIdx else {
            return DayPlan(date: "today", items: [], focusSuggestion: "",
                           summary: "Could not generate plan. Here's your raw context: \(calendarEvents)")
        }

        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let plan = try? JSONDecoder().decode(DayPlan.self, from: data) else {
            return DayPlan(date: "today", items: [], focusSuggestion: "",
                           summary: "Could not generate plan. Here's your raw context: \(calendarEvents)")
        }

        return plan
    }
}
