import Foundation

/// The state of the Pomodoro timer.
enum PomodoroState: Equatable {
    case idle
    case focusing(topic: String)
    case onBreak
}

/// A Pomodoro focus-session timer. Actor-isolated, injectable clock + notify
/// for full testability. Use `PomodoroSession.shared` at runtime; create fresh
/// instances in tests.
actor PomodoroSession {
    static let shared = PomodoroSession()

    private(set) var state: PomodoroState = .idle
    private(set) var minutesRemaining: Int = 0
    private(set) var completedSessions: Int = 0

    /// Duration of the current/most-recent session (stored so tick() can report it).
    private var sessionMinutes: Int = 0
    /// Timestamp when `start()` was called (for elapsed calculation in `stop()`).
    private var startedAt: Date = Date()

    /// Injectable clock — defaults to real `Date()`.
    var now: @Sendable () -> Date = { Date() }

    /// Injectable notification delivery (title, body). Defaults to
    /// `NotificationBridge.shared.send(.agentCompleted(...))`.
    var notify: @Sendable (String, String) async -> Void = { title, body in
        await NotificationBridge.shared.send(.agentCompleted(name: "Pomodoro", summary: body))
    }

    // MARK: - API

    /// Start a new focus session.
    func start(topic: String, minutes: Int = 25) async {
        state = .focusing(topic: topic)
        minutesRemaining = minutes
        sessionMinutes = minutes
        startedAt = now()
    }

    /// Stop the active session. Returns a summary string.
    func stop() async -> String {
        switch state {
        case .idle:
            return "No active session."
        case .focusing(let topic):
            let elapsed = max(0, sessionMinutes - minutesRemaining)
            state = .idle
            minutesRemaining = 0
            return "Session ended. You focused on '\(topic)' for \(elapsed) min."
        case .onBreak:
            state = .idle
            minutesRemaining = 0
            return "Break ended."
        }
    }

    /// Returns a human-readable status string.
    func status() async -> String {
        switch state {
        case .idle:
            return "No active focus session. Start one: 'focus for 25 min on [topic]'"
        case .focusing(let t):
            return "\(minutesRemaining) min remaining — focusing on '\(t)'. Sessions today: \(completedSessions)."
        case .onBreak:
            return "On a break. \(minutesRemaining) min remaining."
        }
    }

    /// Called every minute by AriaController's tick timer. Decrements the counter
    /// and fires a notification when the session completes.
    func tick() async {
        guard case .focusing(let topic) = state else { return }
        if minutesRemaining > 0 {
            minutesRemaining -= 1
        }
        if minutesRemaining == 0 {
            completedSessions += 1
            let minutes = sessionMinutes
            state = .idle
            await notify(
                "Focus session complete",
                "You focused on '\(topic)' for \(minutes) min. Take a break!"
            )
        }
    }
}
