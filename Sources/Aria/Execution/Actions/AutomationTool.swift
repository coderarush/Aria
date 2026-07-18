import Foundation

// MARK: - Shared helper

func triggerDescription(_ trigger: AgentTrigger) -> String {
    switch trigger {
    case .mailMatched(let q):
        return "new email matching '\(q)'"
    case .calendarEventSoon(let t, let m):
        return "calendar event containing '\(t)' starts within \(m) min"
    case .daily(let h, let m):
        return "daily at \(String(format: "%02d:%02d", h, m))"
    case .interval(let s):
        return "every \(Int(s / 60)) minutes"
    case .folderChanged(let p):
        return "folder changes at \(p)"
    case .urlChanged(let u):
        return "URL \(u) changes"
    }
}

// MARK: - AutomationCreateTool

struct AutomationCreateTool: AriaTool {
    static let name = "automation_create"
    static let description = "Create an automation that runs when a trigger fires. Input: name, trigger_type (email/calendar/daily/interval), trigger_value (email query / event title keyword / HH:MM / seconds), goal (what Aria should do when triggered)."
    static let paramHints: [String: String] = [
        "name": "Name for the automation",
        "trigger_type": "email, calendar, daily, or interval",
        "trigger_value": "Email query / event title keyword / HH:MM / seconds",
        "goal": "What Aria should do when triggered"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return .fail("Missing input 'name'. Please provide a name for the automation.")
        }
        guard let triggerType = input["trigger_type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !triggerType.isEmpty else {
            return .fail("Missing input 'trigger_type'. Use: email, calendar, daily, or interval.")
        }
        guard let triggerValue = input["trigger_value"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !triggerValue.isEmpty else {
            return .fail("Missing input 'trigger_value'. Provide an email query, event keyword, HH:MM, or seconds.")
        }
        guard let goal = input["goal"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !goal.isEmpty else {
            return .fail("Missing input 'goal'. Describe what Aria should do when triggered.")
        }

        let trigger: AgentTrigger
        switch triggerType.lowercased() {
        case "email":
            trigger = .mailMatched(query: triggerValue)
        case "calendar":
            trigger = .calendarEventSoon(titleContains: triggerValue, minutesBefore: 10)
        case "daily":
            let parts = triggerValue.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                return .fail("Invalid trigger_value '\(triggerValue)' for daily trigger. Use HH:MM format (e.g., 09:00).")
            }
            trigger = .daily(hour: hour, minute: minute)
        case "interval":
            guard let seconds = Double(triggerValue), seconds > 0 else {
                return .fail("Invalid trigger_value '\(triggerValue)' for interval trigger. Provide seconds as a positive number (e.g., 3600).")
            }
            trigger = .interval(seconds: seconds)
        default:
            return .fail("Unknown trigger_type '\(triggerType)'. Use: email, calendar, daily, or interval.")
        }

        let agent = BackgroundAgent(name: name, goal: goal, trigger: trigger)
        await AgentStore.shared.upsert(agent)

        let desc = triggerDescription(trigger)
        return .ok("Automation '\(name)' created. It will run when: \(desc).")
    }
}

// MARK: - AutomationListTool

struct AutomationListTool: AriaTool {
    static let name = "automation_list"
    static let description = "List all saved automations and their triggers."

    func run(input: [String: String]) async throws -> ToolResult {
        let agents = await AgentStore.shared.all()
        guard !agents.isEmpty else {
            return .ok("No automations yet. Use automation_create to add one.")
        }
        let lines = agents.enumerated().map { idx, agent in
            "\(idx + 1). [\(agent.name)] — \(triggerDescription(agent.trigger)) — Goal: \(agent.goal)"
        }
        return .ok(lines.joined(separator: "\n"))
    }
}
