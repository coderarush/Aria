import Foundation

/// Rotates across multiple Gemini API keys. Each Google project has its own free-tier
/// daily quota, so several free keys multiply the effective free ceiling. When a key
/// hits its quota (429) it's put on cooldown and traffic routes to the next key —
/// directly serving the "always works free" goal.
final class KeyRotator {
    private var keys: [String]
    private var cooldownUntil: [String: Date] = [:]
    private let now: () -> Date

    init(keys: [String] = [], now: @escaping () -> Date = { Date() }) {
        self.keys = keys
        self.now = now
    }

    /// Refresh the key set (the user may add/remove keys at runtime).
    func update(keys: [String]) {
        self.keys = keys
        cooldownUntil = cooldownUntil.filter { keys.contains($0.key) }   // drop stale entries
    }

    var isEmpty: Bool { keys.isEmpty }

    /// The next key not on cooldown (round-robin by declaration order); nil if all
    /// keys are momentarily quota-blocked.
    func reserve() -> String? {
        let t = now()
        return keys.first { key in
            if let until = cooldownUntil[key] { return until <= t }
            return true
        }
    }

    /// Put a key on cooldown after a 429 (default long, since a free-tier DAILY cap
    /// won't free for a while — better to use a different key than to keep hitting it).
    func penalize(_ key: String, seconds: TimeInterval = 90) {
        cooldownUntil[key] = now().addingTimeInterval(seconds)
    }

    /// Seconds until some key is usable again (for pacing when all are blocked).
    func waitTime() -> TimeInterval {
        let t = now()
        let soonest = keys.compactMap { cooldownUntil[$0] }.map { max(0, $0.timeIntervalSince(t)) }.min()
        return (soonest ?? 0) + 0.05
    }
}
