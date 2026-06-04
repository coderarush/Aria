import Foundation

/// Pure decision logic for keeping recognition alive: which session is current (so a
/// superseded task's completion can't trigger a restart) and a watchdog that detects
/// a silently-dead recognizer (no audio flowing). Owned by WakeWordEngine; unit-
/// tested in isolation.
struct RecognitionLifecycle {
    private var current = 0
    private var lastAudioAt: TimeInterval = 0

    /// Begin a new session, superseding the previous one. Returns its id.
    mutating func begin() -> Int { current += 1; return current }

    /// True only if `id` is the current session (a superseded session must not restart).
    func shouldRestart(forSession id: Int) -> Bool { id == current }

    mutating func sawAudio(at t: TimeInterval) { lastAudioAt = t }

    /// True if no audio has arrived within `timeout` seconds — the recognizer is
    /// silently dead and must be rebuilt.
    func watchdogExpired(now: TimeInterval, timeout: TimeInterval) -> Bool {
        now - lastAudioAt > timeout
    }
}
