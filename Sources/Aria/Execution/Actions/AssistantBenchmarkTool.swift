import Foundation

/// Deterministic self-audit against major assistant categories. This is not
/// marketing copy: it gives Aria a compact capability map and prioritized next
/// upgrades the model can use when the user asks "how do we make Aria better?"
struct AssistantBenchmarkTool: AriaTool {
    static let name = "assistant_benchmark"
    static let description = "Compare Aria against Siri-style, command-launcher, and computer-control assistants. Input: {focus?}. Returns strengths, gaps, and concrete next upgrades."
    static let paramHints: [String: String] = [
        "focus": "Optional project or capability to emphasize"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let focus = input["focus"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .ok(AssistantBenchmarkEngine.report(focus: focus?.isEmpty == false ? focus : nil).text)
    }
}

struct AssistantBenchmarkReport: Equatable {
    struct Row: Equatable {
        let area: String
        let siri: String
        let commandLaunchers: String
        let computerControl: String
        let aria: String
    }

    let focus: String?
    let rows: [Row]
    let strengths: [String]
    let gaps: [String]
    let nextUpgrades: [String]

    var text: String {
        var parts: [String] = []
        if let focus { parts.append("Assistant benchmark for \(focus):") }
        else { parts.append("Assistant benchmark:") }

        parts.append("\nCapability matrix:")
        parts.append(rows.map { row in
            "• \(row.area): Siri=\(row.siri); launchers=\(row.commandLaunchers); computer-control=\(row.computerControl); Aria=\(row.aria)"
        }.joined(separator: "\n"))

        parts.append("\nAria advantages:")
        parts.append(strengths.map { "• \($0)" }.joined(separator: "\n"))

        parts.append("\nGaps to close:")
        parts.append(gaps.map { "• \($0)" }.joined(separator: "\n"))

        parts.append("\nNext upgrades:")
        parts.append(nextUpgrades.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        return parts.joined(separator: "\n")
    }
}

enum AssistantBenchmarkEngine {
    static func report(focus: String? = nil) -> AssistantBenchmarkReport {
        let rows = [
            AssistantBenchmarkReport.Row(
                area: "Personal context",
                siri: "strong OS/user context",
                commandLaunchers: "limited unless configured",
                computerControl: "usually task-local",
                aria: "local memory, work journal, goals, imported ChatGPT notes"),
            AssistantBenchmarkReport.Row(
                area: "Screen understanding",
                siri: "visual intelligence on supported surfaces",
                commandLaunchers: "mostly text/commands",
                computerControl: "strong pixel/UI observation",
                aria: "screen OCR, region vision, focused-app context"),
            AssistantBenchmarkReport.Row(
                area: "App operation",
                siri: "system actions and app intents",
                commandLaunchers: "fast commands/extensions",
                computerControl: "direct UI operation",
                aria: "macOS automation, UI tools, connectors, recipes"),
            AssistantBenchmarkReport.Row(
                area: "Autonomy",
                siri: "mostly single-turn",
                commandLaunchers: "manual trigger first",
                computerControl: "task execution",
                aria: "background agents, execution graph, verification, recovery"),
            AssistantBenchmarkReport.Row(
                area: "Trust",
                siri: "platform permissions",
                commandLaunchers: "user-triggered safety",
                computerControl: "varies by agent",
                aria: "confirmation policy, fail-closed background runs, receipts, undo")
        ]

        var next = [
            "Make every high-value workflow installable as a recipe from the conversation.",
            "Expose a live capability dashboard: connectors, permissions, model route, memory status, and safety mode.",
            "Add richer postcondition checks for app/UI actions so Aria can prove the outcome happened.",
            "Improve proactive agents with quiet summaries, diff detection, and explicit escalation reasons.",
            "Turn imported ChatGPT planning into structured projects, entities, recipes, and goals."
        ]

        if let focus, focus.lowercased().contains("aria") {
            next.insert("Run an ARIA-specific build loop: audit → implement → test → update website/video → save launch notes.", at: 0)
        }

        return AssistantBenchmarkReport(
            focus: focus,
            rows: rows,
            strengths: [
                "Combines voice, screen context, tools, memory, workflows, and receipts in one loop.",
                "Local-first design keeps the Mac as the control plane instead of forcing a backend.",
                "Background agents and recipes make repeated work durable instead of trapped in chats.",
                "Safety gates are part of execution, not a separate disclaimer."
            ],
            gaps: [
                "Needs more structured conversion from conversation history into projects/goals/recipes.",
                "Needs more first-run onboarding that explains permissions through the blob’s state changes.",
                "Needs broader connector coverage and clearer degraded-mode behavior when a connector is missing.",
                "Needs more visual verification for UI automation outcomes."
            ],
            nextUpgrades: next)
    }
}
