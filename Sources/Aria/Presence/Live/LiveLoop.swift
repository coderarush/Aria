import Foundation

/// What one evaluation decided — exposed for tests and the activity log.
enum LiveLoopOutcome: Sendable, Equatable {
    /// An auto-tier playbook was dispatched.
    case acted(playbookID: String, command: String)
    /// A confirm-tier playbook surfaced as a card/offer.
    case offered(playbookID: String, suggestion: Suggestion)
    /// Nothing fired this cycle.
    case idle
}

/// The always-on Perceive → Anticipate → Act → Remember cycle (Live Loop
/// design 2026-06-24). An actor that:
///  - folds `LiveSignal`s into a `PresenceContext` (perceive),
///  - runs the `OpportunityDetector` + `OpportunityRanker` (anticipate),
///  - resolves the top opportunity's `Playbook` and either dispatches it
///    through the existing orchestrator (auto tier) or surfaces a card via the
///    existing `SuggestionPresenter` (confirm tier) (act),
///  - records every outcome to long-term memory (remember).
///
/// Runs on signal events plus a low-frequency idle tick — never a hot loop.
/// LLM work happens only inside a fired playbook.
actor LiveLoop {

    /// Everything the loop needs from the outside world, injected for tests.
    struct Dependencies: Sendable {
        var signals: [any LiveSignal]
        var rules: [any OpportunityRule]
        var settings: @Sendable () -> LiveLoopSettings
        var proactiveSettings: @Sendable () -> ProactiveSettings
        var store: LiveLoopStore
        var isLowPower: @Sendable () -> Bool
        /// Whether Aria may act/surface right now (idle, no pending card).
        var canSurface: @Sendable () async -> Bool
        /// Dispatch an auto-tier playbook command through the live orchestrator.
        var act: @Sendable (_ command: String, _ narration: String) async -> Void
        /// Surface a confirm-tier offer through the live presenter.
        var offer: @Sendable (Suggestion) async -> Void
        /// Write an outcome line to long-term memory.
        var remember: @Sendable (String) async -> Void
        var now: @Sendable () -> Date

        init(signals: [any LiveSignal],
             rules: [any OpportunityRule],
             settings: @escaping @Sendable () -> LiveLoopSettings = { .load() },
             proactiveSettings: @escaping @Sendable () -> ProactiveSettings = { .load() },
             store: LiveLoopStore = LiveLoopStore(),
             isLowPower: @escaping @Sendable () -> Bool = {
                 ProcessInfo.processInfo.isLowPowerModeEnabled
             },
             canSurface: @escaping @Sendable () async -> Bool = { true },
             act: @escaping @Sendable (String, String) async -> Void = { _, _ in },
             offer: @escaping @Sendable (Suggestion) async -> Void = { _ in },
             remember: @escaping @Sendable (String) async -> Void = { _ in },
             now: @escaping @Sendable () -> Date = { Date() }) {
            self.signals = signals
            self.rules = rules
            self.settings = settings
            self.proactiveSettings = proactiveSettings
            self.store = store
            self.isLowPower = isLowPower
            self.canSurface = canSurface
            self.act = act
            self.offer = offer
            self.remember = remember
            self.now = now
        }
    }

    private let deps: Dependencies
    private let detector = OpportunityDetector()
    private let ranker = OpportunityRanker()
    private var tickTask: Task<Void, Never>?
    private var rulesRegistered = false

    init(deps: Dependencies) {
        self.deps = deps
    }

    deinit { tickTask?.cancel() }

    // MARK: Lifecycle

    /// Begin the idle tick. Signal events additionally call `nudge()`.
    func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = max(15, self.deps.settings().tickSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                _ = await self.evaluate()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Event-driven evaluation (app switch, new mail observation, wake).
    func nudge() async {
        _ = await evaluate()
    }

    // MARK: The cycle

    @discardableResult
    func evaluate() async -> LiveLoopOutcome {
        let now = deps.now()
        let settings = deps.settings()
        guard settings.enabled else { return .idle }
        if settings.pauseInLowPower, deps.isLowPower() { return .idle }
        if !rulesRegistered {
            for rule in deps.rules { await detector.addRule(rule) }
            rulesRegistered = true
        }

        // Perceive.
        var context = PresenceContext()
        for signal in deps.signals {
            context = await signal.apply(to: context, now: now)
        }

        // Anticipate.
        let proactive = deps.proactiveSettings()
        let quiet = proactive.quietHoursEnabled && proactive.quietHours.contains(now)
        let candidates = await detector.detect(context).filter { opportunity in
            guard let ref = opportunity.playbook else { return false }
            let tier = settings.tier(for: ref.id)
            guard tier != .off else { return false }
            guard !deps.store.isNever(ref.id) else { return false }
            guard !deps.store.isSnoozed(ref.id, now: now) else { return false }
            guard !deps.store.isCoolingDown(ref.id, now: now) else { return false }
            // Quiet hours hold everything except imminent-meeting prep.
            if quiet && ref.id != PlaybookLibrary.meetingPrep { return false }
            return true
        }
        guard let top = ranker.rank(candidates).first,
              let ref = top.playbook,
              let resolved = PlaybookLibrary.resolve(ref) else { return .idle }

        // Act — only when Aria isn't speaking/mid-task and no card is pending.
        guard await deps.canSurface() else { return .idle }
        deps.store.markFired(ref.id, now: now)
        if ref.id == PlaybookLibrary.dailyBrief { deps.store.markBriefRan(on: now) }

        switch settings.tier(for: ref.id) {
        case .auto:
            await deps.act(resolved.command, resolved.offer)
            await deps.remember(
                "Live Loop auto-ran “\(resolved.playbook.title)” (\(top.reason)).")
            return .acted(playbookID: ref.id, command: resolved.command)
        case .confirm:
            let suggestion = Suggestion(
                source: Self.source(for: ref.id),
                spokenLine: resolved.offer,
                action: .runCommand(resolved.command),
                confidence: top.confidence,
                urgency: ref.id == PlaybookLibrary.meetingPrep ? .timeCritical : .ambient,
                createdAt: now,
                expiry: now.addingTimeInterval(10 * 60),
                dedupeKey: "liveloop.\(ref.id)")
            await deps.offer(suggestion)
            await deps.remember(
                "Live Loop offered “\(resolved.playbook.title)” (\(top.reason)).")
            return .offered(playbookID: ref.id, suggestion: suggestion)
        case .off:
            return .idle
        }
    }

    /// Map a playbook to the closest existing suggestion source so the
    /// per-source proactive toggles and suppression bookkeeping apply cleanly.
    static func source(for playbookID: String) -> SuggestionSource {
        switch playbookID {
        case PlaybookLibrary.meetingPrep, PlaybookLibrary.dailyBrief: return .calendar
        case PlaybookLibrary.screenCoPilot: return .screen
        default: return .session
        }
    }
}
