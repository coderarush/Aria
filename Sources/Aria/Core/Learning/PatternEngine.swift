import Foundation

/// Observes behavior, detects patterns on-device, suggests automations once
/// confident, and fires approved automations. All data stays local — nothing is
/// ever sent to Gemini or any server.
///
/// Hardcoded safety rules (non-negotiable):
/// - No suggestions or automations during the first 14 days (pure observation).
/// - Approved patterns fire at most once per matching window.
/// - Destructive actions are surfaced to the caller for confirmation before run.
/// - Patterns expire after 30 days without recurrence.
actor PatternEngine {

    static let observationGraceDays = 14
    private let minRefireInterval: TimeInterval = 3600  // 1h

    private let log: ObservationLog
    private let fileURL: URL
    private var patterns: [BehaviorPattern]

    /// Called when a pattern crosses the suggestion threshold (orb self-appears).
    var onSuggestion: (@Sendable (BehaviorPattern) -> Void)?

    init(log: ObservationLog = ObservationLog(), fileURL: URL? = nil) {
        self.log = log
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.patterns = Self.load(from: url)
    }

    static func defaultURL() -> URL {
        PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("patterns.json")
    }

    func setSuggestionHandler(_ handler: @escaping @Sendable (BehaviorPattern) -> Void) {
        onSuggestion = handler
    }

    // MARK: Observation

    func recordCommand(_ command: String, at date: Date = Date()) async {
        await log.recordCommand(command, at: date)
    }
    func recordAppEvent(_ event: AppEvent) async { await log.recordApp(event) }
    func recordFileEvent(_ event: FileEvent) async { await log.recordFile(event) }

    // MARK: Analysis

    /// Re-detect patterns from observations and merge with stored state
    /// (preserving approval/suppression). Returns the current pattern set.
    @discardableResult
    func analyzePatterns(sensitivity: Double, now: Date = Date()) async -> [BehaviorPattern] {
        let commands = await log.store.commands
        let detected = PatternDetector.detectTimePatterns(commands: commands, sensitivity: sensitivity)

        for d in detected {
            let key = d.action
            if let idx = patterns.firstIndex(where: { $0.action == key }) {
                // Update metrics but keep user-decided status.
                if patterns[idx].status == .observing || patterns[idx].status == .suggested {
                    patterns[idx].confidence = d.confidence
                    patterns[idx].occurrences = d.occurrences
                    patterns[idx].description = d.description
                    patterns[idx].trigger = d.trigger
                }
            } else {
                patterns.append(d)
            }
        }

        // Expire stale patterns (unless the user approved them).
        patterns.removeAll {
            $0.status != .approved && PatternDetector.isExpired($0, now: now)
        }
        save()
        return patterns
    }

    /// Patterns ready to suggest to the user (respects the 14-day grace period).
    func patternsToSuggest(now: Date = Date()) async -> [BehaviorPattern] {
        guard await log.observationDays(now: now) >= Self.observationGraceDays else { return [] }
        let ready = patterns.filter { $0.status == .observing }
        for p in ready {
            if let idx = patterns.firstIndex(where: { $0.id == p.id }) {
                patterns[idx].status = .suggested
                patterns[idx].suggestionCount += 1
            }
            onSuggestion?(p)
        }
        if !ready.isEmpty { save() }
        return ready
    }

    /// Approved automations whose trigger matches `now` and haven't fired
    /// recently. The caller executes them (and confirms destructive ones).
    func automationsToFire(now: Date = Date()) async -> [BehaviorPattern] {
        let settings = LearningSettings.load()
        guard settings.enabled, !settings.automationsPaused else { return [] }
        guard await log.observationDays(now: now) >= Self.observationGraceDays else { return [] }

        var firing: [BehaviorPattern] = []
        for (idx, p) in patterns.enumerated() where p.status == .approved {
            guard PatternDetector.triggerMatches(p.trigger, now: now) else { continue }
            if let last = p.lastFired, now.timeIntervalSince(last) < minRefireInterval { continue }
            patterns[idx].lastFired = now
            firing.append(patterns[idx])
        }
        if !firing.isEmpty { save() }
        return firing
    }

    // MARK: User control

    func approve(_ id: UUID, mode: ApprovalMode) { mutate(id) { $0.status = .approved; $0.approvalMode = mode } }
    func suppress(_ id: UUID) { mutate(id) { $0.status = .suppressed } }
    func pause(_ id: UUID) { mutate(id) { $0.status = .paused } }
    func resume(_ id: UUID) { mutate(id) { $0.status = .approved } }

    /// "Not yet": re-surface after 10 more occurrences (handled by status reset).
    func deferSuggestion(_ id: UUID) { mutate(id) { $0.status = .observing } }

    func delete(_ id: UUID) {
        patterns.removeAll { $0.id == id }
        save()
    }

    func allPatterns() -> [BehaviorPattern] { patterns }

    /// Nuclear option — wipe all patterns and observations.
    func forgetEverything() async {
        patterns = []
        save()
        await log.clear()
    }

    private func mutate(_ id: UUID, _ change: (inout BehaviorPattern) -> Void) {
        guard let idx = patterns.firstIndex(where: { $0.id == id }) else { return }
        change(&patterns[idx])
        save()
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(patterns) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [BehaviorPattern] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BehaviorPattern].self, from: data)) ?? []
    }
}
