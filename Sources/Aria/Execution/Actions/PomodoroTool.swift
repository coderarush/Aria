import Foundation

// MARK: - Start

/// Start a Pomodoro focus session.
struct PomodoroStartTool: AriaTool {
    static let name = "pomodoro_start"
    static let description = "Start a Pomodoro focus session. Input: {topic} (required), {minutes} (optional, default 25, 1–120)."
    static let paramHints: [String: String] = [
        "topic":   "What you'll be focusing on",
        "minutes": "Duration in minutes (default 25, max 120)"
    ]

    private let session: PomodoroSession

    init(session: PomodoroSession = PomodoroSession.shared) {
        self.session = session
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let topic = input["topic"] ?? ""
        let rawMinutes = input["minutes"].flatMap { Int($0) } ?? 25
        let minutes = min(120, max(1, rawMinutes))

        await session.start(topic: topic, minutes: minutes)
        return .ok("Focus session started. \(minutes) min on '\(topic)'. I'll notify you when time's up. Use 'pomodoro status' to check in.")
    }
}

// MARK: - Stop

/// Stop the active Pomodoro session.
struct PomodoroStopTool: AriaTool {
    static let name = "pomodoro_stop"
    static let description = "Stop the current Pomodoro focus session and get a summary."

    private let session: PomodoroSession

    init(session: PomodoroSession = PomodoroSession.shared) {
        self.session = session
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let summary = await session.stop()
        return .ok(summary)
    }
}

// MARK: - Status

/// Query the current Pomodoro session status.
struct PomodoroStatusTool: AriaTool {
    static let name = "pomodoro_status"
    static let description = "Check the status of the current Pomodoro focus session."

    private let session: PomodoroSession

    init(session: PomodoroSession = PomodoroSession.shared) {
        self.session = session
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let status = await session.status()
        return .ok(status)
    }
}
