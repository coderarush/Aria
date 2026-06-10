import Foundation

/// The brain of Proactive Presence. Gathers candidate suggestions from its
/// enabled providers, drops the expired / suppressed / quiet-hours ones, ranks
/// what's left, de-duplicates by `dedupeKey`, and returns at most the single
/// best live suggestion. Feedback (accept/dismiss/expire) is recorded back into
/// a durable `ProactiveStore`.
///
/// An actor: providers may be polled concurrently and `record` mutates the store.
actor ProactiveEngine {

    private let providers: [any SignalProvider]
    private let settings: @Sendable () -> ProactiveSettings
    private let storeURL: URL
    private var store: ProactiveStore

    init(providers: [any SignalProvider],
         settings: @escaping @Sendable () -> ProactiveSettings,
         storeURL: URL? = nil) {
        self.providers = providers
        self.settings = settings
        let url = storeURL ?? ProactiveStoreFile.defaultURL()
        self.storeURL = url
        self.store = ProactiveStoreFile.load(from: url)
    }

    /// The single best suggestion to surface right now, or nil if there's nothing
    /// worth interrupting for.
    func tick(now: Date) async -> Suggestion? {
        let config = settings()
        guard config.enabled else { return nil }

        var candidates: [Suggestion] = []
        for provider in providers where config.isSourceEnabled(provider.source) {
            candidates += await provider.candidates(now: now)
        }

        let quiet = config.quietHoursEnabled && config.quietHours.contains(now)
        var live = candidates.filter { s in
            !s.isExpired(now: now) && !store.isSuppressed(key: s.dedupeKey, now: now)
        }
        if quiet { live = live.filter { $0.urgency == .timeCritical } }

        // Best-first, then keep one per dedupe key.
        let ranked = live.sorted(by: Suggestion.rank)
        var seen = Set<String>()
        for s in ranked where !seen.contains(s.dedupeKey) {
            seen.insert(s.dedupeKey)
            return s   // first survivor is the best
        }
        return nil
    }

    /// Record how the user responded, update suppression, and persist.
    func record(_ outcome: SuggestionOutcome, for suggestion: Suggestion, now: Date) {
        store.record(outcome, key: suggestion.dedupeKey, now: now)
        ProactiveStoreFile.save(store, to: storeURL)
    }
}
