import Foundation

enum FocusDepth: String, Sendable { case idle, shallow, deep }

struct AttentionState: Equatable, Sendable {
    var activeApp: String?
    var focusMinutes: Double
    var depth: FocusDepth
    var shouldInterrupt: Bool
    var rationale: String
}

/// AttentionEngine (Phase 13): metrics + an interrupt gate, computed — not stored
/// and not re-tracked. It reads the existing AppFocusMonitor (current app + when
/// focus began) and derives the current focus depth, so Aria interrupts less
/// during deep focus and suggests more when idle. No persistence, no second
/// focus tracker.
///
/// Note: AppFocusMonitor keeps only the *current* focus session (no history), so
/// depth is the current session's duration — honest about what's available.
struct AttentionEngine {
    private let monitor: AppFocusMonitor
    private let deepThreshold: TimeInterval

    init(monitor: AppFocusMonitor = .shared, deepThreshold: TimeInterval = 600) {
        self.monitor = monitor
        self.deepThreshold = deepThreshold
    }

    func state(now: Date = Date()) async -> AttentionState {
        guard let focus = await monitor.snapshot() else {
            return AttentionState(activeApp: nil, focusMinutes: 0, depth: .idle,
                                  shouldInterrupt: true, rationale: "idle — no active focus, fine to suggest")
        }
        let seconds = max(0, now.timeIntervalSince(focus.since))
        let depth: FocusDepth = seconds >= deepThreshold ? .deep : .shallow
        let interrupt = depth != .deep
        let rationale = depth == .deep
            ? "deep focus in \(focus.appName) (\(Int(seconds / 60))m) — hold non-urgent interruptions"
            : "shallow focus in \(focus.appName) — ok to surface suggestions"
        return AttentionState(activeApp: focus.appName, focusMinutes: seconds / 60,
                              depth: depth, shouldInterrupt: interrupt, rationale: rationale)
    }

    /// Whether Aria should interrupt now — false during deep focus.
    func shouldInterrupt(now: Date = Date()) async -> Bool {
        await state(now: now).shouldInterrupt
    }
}
