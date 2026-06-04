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

    init(models: [String], perMinuteLimit: Int = 14, now: @escaping () -> Date = { Date() }) {
        self.models = models
        self.perMinuteLimit = perMinuteLimit
        self.now = now
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-window)
        for m in models { history[m] = (history[m] ?? []).filter { $0 > cutoff } }
    }

    /// Reserve a model with capacity now, recording the request; nil if all maxed.
    func reserve() -> String? {
        prune()
        for model in models {
            if (history[model]?.count ?? 0) < perMinuteLimit {
                history[model, default: []].append(now())
                return model
            }
        }
        return nil
    }

    /// Seconds until the soonest bucket frees a slot.
    func waitTime() -> TimeInterval {
        prune()
        let oldest = models.compactMap { history[$0]?.min() }.min()
        guard let oldest else { return 0 }
        return max(0, window - now().timeIntervalSince(oldest)) + 0.05
    }
}
