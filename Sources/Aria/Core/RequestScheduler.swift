import Foundation

/// Spreads model calls across per-model free-tier buckets and reports how long to
/// wait when all buckets are momentarily maxed — so calls pace instead of failing.
/// `now` is injectable for tests. Plain final class; the owning GeminiClient actor
/// serializes access.
final class RequestScheduler {
    private let models: [String]
    private let perMinuteLimit: Int
    private let window: TimeInterval = 60
    private let now: () -> Date
    private var history: [String: [Date]] = [:]
    private var blockedUntil: [String: Date] = [:]

    init(models: [String], perMinuteLimit: Int = 14, now: @escaping () -> Date = { Date() }) {
        self.models = models
        self.perMinuteLimit = perMinuteLimit
        self.now = now
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-window)
        for m in models { history[m] = (history[m] ?? []).filter { $0 > cutoff } }
    }

    /// Record a call against a model's bucket without going through reserve()
    /// (used when a caller forces a specific/preferred model so accounting stays honest).
    func record(_ model: String) {
        prune()
        history[model, default: []].append(now())
    }

    /// Mark a model as rate-limited (after a server 429) so reserve() routes around
    /// it until the cooldown passes. This is what turns a server 429 — which fires
    /// long before the local per-minute counter fills — into REAL pacing instead of
    /// a hot spin that exhausts the retry budget and hard-fails.
    func penalize(_ model: String, seconds: TimeInterval = 30) {
        blockedUntil[model] = now().addingTimeInterval(seconds)
    }

    /// Reserve a model that is under its local limit AND not rate-limited; record
    /// the request. nil if every model is busy.
    func reserve() -> String? {
        prune()
        let t = now()
        for model in models {
            if let until = blockedUntil[model], until > t { continue }     // 429 cooldown
            if (history[model]?.count ?? 0) < perMinuteLimit {
                history[model, default: []].append(t)
                return model
            }
        }
        return nil
    }

    /// Seconds until the soonest model becomes available (unblocked AND under limit).
    func waitTime() -> TimeInterval {
        prune()
        let t = now()
        let perModel: [TimeInterval] = models.map { m in
            let blockWait = blockedUntil[m].map { max(0, $0.timeIntervalSince(t)) } ?? 0
            let full = (history[m]?.count ?? 0) >= perMinuteLimit
            let histWait = (full ? history[m]?.min().map { max(0, window - t.timeIntervalSince($0)) } : nil) ?? 0
            return max(blockWait, histWait)
        }
        return (perModel.min() ?? 0) + 0.05
    }
}
