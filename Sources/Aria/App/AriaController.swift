import SwiftUI
import AppKit
import Combine
import EventKit
import Carbon.HIToolbox

/// Top-level coordinator that owns the runtime engines and the Island panel, and
/// wires wake → listen → think → respond. Lives for the app's lifetime.
@MainActor
final class AriaController {

    let islandViewModel = IslandViewModel()
    private let audioBus = AudioBus()
    private let wakeEngine = WakeWordEngine()
    private let voice = VoiceEngine()
    private let bargeController = BargeController()
    private let speakerGate = SpeakerGate()
    private let computerUseIndicator = ComputerUseIndicator()
    private let orchestrator = AgentOrchestrator()
    private let patternEngine = PatternEngine()
    private var panel: IslandPanel?
    private let taskViewModel = TaskViewModel()
    private var taskPanel: TaskPanel?
    private var learningTimer: Timer?
    // Proactive Presence (v9): ambient anticipation that surfaces a single
    // suggestion silently on the orb and speaks it only when you wake/glance.
    private var proactiveEngine: ProactiveEngine?
    private var proactivePresenter: SuggestionPresenter?
    private var proactiveTimer: Timer?
    private var proactiveExpiryTimer: Timer?
    /// True between revealing a suggestion and hearing the user's yes/no, so the
    /// next command is interpreted as the answer.
    private var proactiveAwaitingReply = false
    /// Pending plan-preview decision: the next spoken/typed reply resolves it.
    private var planDecision: CheckedContinuation<Bool, Never>?
    private var planDecisionTimer: Timer?
    /// Background agents (v9): recurring workflows + folder watchers, run
    /// silently through the same autonomy engine + safety gates.
    private var agentCoordinator: AgentCoordinator?
    /// Push-to-talk (⌥Space) and type-to-Aria (⌥⇧Space) global hotkeys.
    private var hotkeyTap: HotkeyTap?
    private var typePanel: CommandInputPanel?
    private var settingsCancellable: AnyCancellable?
    /// True while Aria is speaking; keeps wake suspended even if the pill
    /// auto-hides mid-utterance, so she can't hear herself and re-trigger.
    private var isSpeaking = false
    private var streamVoice: StreamingVoice!
    private var session: ConversationSession?
    private var convSilenceTimer: Timer?
    /// True while an autonomous task is executing. Gates `streamVoice.onAllFinished`
    /// so a queue-drain mid-task (e.g. after the spoken plan) doesn't re-arm wake
    /// before the task is actually done.
    private var taskActive = false
    /// The in-flight streaming turn task; cancelled on barge-in.
    private var currentTurnTask: Task<Void, Never>?
    /// When the current TTS turn started; used to enforce a 0.5 s arm-grace
    /// so we don't immediately barge-in on the very first audio burst.
    private var speechStartedAt = Date.distantPast

    func start() {
        Log.trace("start: begin")
        // Pre-warm Combine's Published generic metadata ON THE MAIN THREAD before
        // the audio pipeline starts. In debug builds (no metadata
        // prespecialization) the first instantiation under concurrency — audio
        // thread feeding levels vs main thread — deadlocked the main thread in
        // MetadataCacheEntryBase::awaitSatisfyingState (sampled live).
        islandViewModel.updateAudioLevel(0)
        islandViewModel.updateAudioLevel(0.01)
        setupPanel();              Log.trace("start: panel")
        wireEngine();              Log.trace("start: engine wired")
        configureConfirmation()
        configureLearning();       Log.trace("start: learning")
        startListening()
        offerResumeIfPending()
        reindexKnowledgeIfEnabled()
        // Bisect kill-switches: `defaults write com.aria.agent app.disableX -bool true`
        let d = UserDefaults.standard
        if !d.bool(forKey: "app.disableAgents") { configureBackgroundAgents(); Log.trace("start: agents") }
        if !d.bool(forKey: "app.disableHotkeys") { configureHotkeys() }
        configureDebugHooks()
        warmLocalModel()
        Log.trace("start: done")
    }

    /// Pull the local model into RAM right after launch so the FIRST real turn
    /// doesn't pay the cold-load + prompt-eval penalty (measured ~2-3 min cold
    /// on a 4B model with the full tool catalog; warm it's seconds). Quiet,
    /// background, only when local-first is on and a server is reachable.
    private func warmLocalModel() {
        Task.detached(priority: .utility) {
            let router = LocalFirstRouter()
            guard await router.chatGoesLocal() else { return }
            let model = router.localModelName.isEmpty ? OllamaProvider.defaultModel : router.localModelName
            let provider = OllamaProvider(model: model)
            Log.trace("local: warming \(model)…")
            let start = Date()
            _ = try? await provider.generateText(prompt: "Reply with: ok", temperature: 0)
            Log.trace("local: warm in \(Int(Date().timeIntervalSince(start)))s")
            // Keep it resident: Ollama unloads after ~5 idle minutes, which
            // would put the cold-load penalty back on the next conversation.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 240_000_000_000)   // 4 min
                guard await router.chatGoesLocal() else { continue }
                _ = try? await provider.generateText(prompt: "ok", temperature: 0)
            }
        }
    }

    /// Global hotkeys: ⌥Space = push-to-talk summon (coexists with the wake
    /// phrase), ⌥⇧Space = type to Aria. CGEvent tap (consumes the keystroke;
    /// rides the Accessibility trust Aria already has for computer use).
    private func configureHotkeys() {
        hotkeyTap = HotkeyTap(
            onTalk: { [weak self] in self?.summonAria() },
            onType: { [weak self] in self?.showTypePanel() })
        if hotkeyTap?.start() != true {
            // Accessibility not granted yet (or granted AFTER launch — taps
            // can't be created retroactively). Keep retrying so the user never
            // has to relaunch after flipping the toggle in System Settings.
            retryHotkeysUntilLive()
        }
        typePanel = CommandInputPanel { [weak self] text in
            self?.handleTypedCommand(text)
        }
    }

    private func retryHotkeysUntilLive(attempt: Int = 0) {
        guard attempt < 120 else { return }   // give up after ~30 min
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, let tap = self.hotkeyTap else { return }
            if tap.start() {
                Log.trace("hotkeys: live after retry \(attempt + 1)")
            } else {
                self.retryHotkeysUntilLive(attempt: attempt + 1)
            }
        }
    }

    /// Push-to-talk: same flow as hearing "Hey Aria". The engine no-ops while
    /// suspended (she's speaking) or already capturing.
    func summonAria() {
        wakeEngine.summon()
    }

    /// Soft interaction chime, AEC-cancelled (played as far-end reference so
    /// the mic never hears it). Deferred off the caller's stack so it can never
    /// block the wake path; subtle by design; toggleable in Settings.
    private func playChime(_ kind: UISounds.Kind) {
        guard AppSettings.shared.uiSoundsEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Log.trace("chime: \(kind) start")
            let samples = UISounds.pcm(for: kind)
            var pcm = Data(capacity: samples.count * 2)
            for s in samples {
                var le = s.littleEndian
                withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
            }
            self.audioBus.playReference(pcm: pcm, pcmRate: UISounds.sampleRate) {
                Log.trace("chime: \(kind) done")
            }
        }
    }

    /// Local debug hooks for headless driving (summon + typed commands) so the
    /// capture pipeline can be exercised and traced without a microphone.
    /// Off unless `defaults write com.aria.agent app.debugHooks -bool true`.
    private func configureDebugHooks() {
        guard UserDefaults.standard.bool(forKey: "app.debugHooks") else { return }
        Log.trace("debug hooks ON")
        // Selector API with .deliverImmediately — the block API holds
        // notifications for background (LSUIElement) apps until activation.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(debugSummon),
                        name: Notification.Name("aria.debug.summon"), object: nil,
                        suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(debugSay(_:)),
                        name: Notification.Name("aria.debug.say"), object: nil,
                        suspensionBehavior: .deliverImmediately)
    }

    @objc private func debugSummon() { summonAria() }

    @objc private func debugSay(_ note: Notification) {
        let text = note.object as? String ?? ""
        Log.trace("debug.say: '\(text)'")
        handleTypedCommand(text)
    }

    func showTypePanel() {
        typePanel?.present()
    }

    /// Menu bar "Pause listening": hard-mutes the wake word and push-to-talk
    /// until turned back off. The mic stays technically open (tearing the
    /// audio engine down and back up is the historic source of deafness bugs)
    /// — Aria simply ignores everything she hears.
    var isListeningPaused: Bool {
        get { wakeEngine.manuallyMuted }
        set {
            wakeEngine.manuallyMuted = newValue
            Log.trace("listening \(newValue ? "PAUSED" : "resumed") via menu")
            if newValue { islandViewModel.dismiss() }
        }
    }

    /// One-line status for the menu bar: what Aria last did.
    func lastActivityLine() async -> String? {
        if let run = await AgentStore.shared.recentRuns(1).first {
            let when = run.date.formatted(date: .omitted, time: .shortened)
            return "\(run.ok ? "✓" : "✗") \(run.agentName) — \(when)"
        }
        return nil
    }

    /// A typed command enters the exact same conversation pipeline as speech.
    func handleTypedCommand(_ text: String) {
        if session == nil {
            wakeEngine.conversationActive = true
            session = ConversationSession(
                onEnd: { [weak self] in self?.endConversation() },
                onTurn: { [weak self] in self?.handleCommand($0) })
            session?.start()
        }
        islandViewModel.beginListening()
        convSilenceTimer?.invalidate()
        session?.userSaid(text)
    }

    /// Background agents run due goals through the normal autonomy engine —
    /// same tools, same Safety gates — but silently: no voice, no orb takeover.
    /// Completion always notifies (never hidden), and runs land in history.
    private func configureBackgroundAgents() {
        let coordinator = AgentCoordinator(
            isBusy: { [weak self] in
                guard let self else { return true }
                return self.isSpeaking || self.taskActive || self.wakeEngine.conversationActive
            },
            runner: { [weak self] goal in
                guard let self else { return (false, "unavailable") }
                return await self.runSilentTask(goal: goal)
            },
            notify: { title, body in
                Notifier.notify(title: title, body: body)
            })
        agentCoordinator = coordinator
        coordinator.start()
        // Settings tab posts this after any agent add/remove/toggle.
        NotificationCenter.default.addObserver(forName: .ariaAgentsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.agentCoordinator?.refreshWatchers() }
        }
    }

    /// Run one autonomy goal without touching the voice/orb surfaces; returns
    /// the engine's final summary.
    private func runSilentTask(goal: String) async -> (Bool, String) {
        // The daily briefing is composed deterministically, not planned —
        // crafted output, fixed inputs, no model roulette.
        if goal == BriefingComposer.agentSentinel {
            let (text, ok) = await deliverBriefing(silent: true)
            return (ok, String(text.prefix(140)))
        }
        actor ResultBox {
            var value: (Bool, String)?
            func set(_ v: (Bool, String)) { if value == nil { value = v } }
        }
        let box = ResultBox()
        await orchestrator.runTask(goal: goal, silent: true) { event in
            if case .finished(let ok, let summary) = event {
                Task { await box.set((ok, summary)) }
            }
        }
        // The finished event may land via a detached Task — give it a moment.
        for _ in 0..<20 {
            if let v = await box.value { return v }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (false, "The task ended without reporting a result.")
    }

    /// Refresh the local knowledge index shortly after launch (incremental —
    /// unchanged files are skipped, so steady-state cost is a folder walk).
    /// Strictly opt-in via Settings → Knowledge.
    private func reindexKnowledgeIfEnabled() {
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)   // let launch settle
            let settings = KnowledgeSettings.load()
            guard settings.enabled, !settings.folders.isEmpty else { return }
            let stats = await KnowledgeIndex.shared.reindex(folders: settings.folders)
            Log.trace("knowledge: reindexed \(stats.indexed), skipped \(stats.skipped), removed \(stats.removed)")
        }
    }

    /// If a multi-step task was interrupted (crash/quit), proactively surface it once
    /// startup has settled — a single system notification, nothing intrusive. The user
    /// continues by voice ("Hey Aria, resume"); we never auto-run a task on launch.
    private func offerResumeIfPending() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // let launch settle first
            guard let self, let pending = await self.orchestrator.pendingTask() else { return }
            let remaining = pending.unfinishedCount
            let msg = "Unfinished task: “\(pending.goal)” — \(remaining) step\(remaining == 1 ? "" : "s") left. Say “Hey Aria, resume” to continue."
            Notifier.notify(title: "Aria", body: msg)
            Log.trace("resume: offered pending task '\(pending.goal)'")
        }
    }

    private var previewWindow: NSWindow?

    /// Preview mode (used for screenshots/docs): shows the island in a plain titled
    /// window on a dark backdrop, without starting the mic so there is no TCC
    /// prompt. The production island lives in a borderless non-activating panel,
    /// which doesn't capture cleanly; this window does. Triggered by the
    /// `/tmp/aria_show_orb` sentinel or the `ARIA_SHOW_ORB` env var.
    func startForScreenshot() {
        // Defer off the launch call stack so the runloop is up before building
        // the hosting view.
        DispatchQueue.main.async { [weak self] in self?.buildPreviewWindow() }
    }

    private func buildPreviewWindow() {
        islandViewModel.beginListening()
        islandViewModel.updateAudioLevel(0.6)

        let root = ZStack {
            Color.black
            IslandView(viewModel: islandViewModel)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Aria — Island Preview"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        previewWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Publish the window number so a screenshot script can target it.
        try? "\(window.windowNumber)".write(toFile: "/tmp/aria_window.txt", atomically: true, encoding: .utf8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.islandViewModel.showResponse("**Aria** is online.\nSay *Hey Aria* to begin.")
            self?.previewWindow?.orderFrontRegardless()
        }
    }

    // MARK: Behavioral learning

    private func configureLearning() {
        observeAppEvents()
        configureProactive()
        // Hourly: re-detect patterns + fire approved automations. Suggestions now
        // surface ambiently through the Proactive engine, not a blocking modal.
        learningTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runLearningCycle() }
        }
    }

    private func observeAppEvents() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundle = app.bundleIdentifier else { return }
            Task { await self?.patternEngine.recordAppEvent(AppEvent(bundleId: bundle, kind: .launched, timestamp: Date())) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundle = app.bundleIdentifier else { return }
            Task { await self?.patternEngine.recordAppEvent(AppEvent(bundleId: bundle, kind: .quit, timestamp: Date())) }
        }
    }

    private func runLearningCycle() async {
        let sensitivity = LearningSettings.load().sensitivity
        _ = await patternEngine.analyzePatterns(sensitivity: sensitivity)
        let firing = await patternEngine.automationsToFire()
        for pattern in firing {
            if case let .runSavedCommand(command) = pattern.action {
                Log.app.info("Firing automation: \(command, privacy: .public)")
                islandViewModel.beginThinking()
                let response = await orchestrator.handle(command: command)
                islandViewModel.showResponse("⚡️ " + response.message)
            }
        }
    }

    // MARK: Proactive Presence (v9)

    /// Build the engine, providers (calendar + learned routines), and presenter,
    /// then poll gently for something worth offering.
    private func configureProactive() {
        guard !UserDefaults.standard.bool(forKey: "app.disableProactive") else { return }
        let pe = patternEngine
        let calendar = CalendarSignalProvider(leadWindow: 300) { now in
            await Self.upcomingCalendarEvents(now: now, window: 360)
        }
        let routine = RoutineSignalProvider { now in
            await pe.patternsToSuggest(now: now)
        }
        let engine = ProactiveEngine(providers: [calendar, routine],
                                     settings: { ProactiveSettings.load() })
        proactiveEngine = engine

        let surface = ProactiveSurfaceAdapter(controller: self)
        proactivePresenter = SuggestionPresenter(surface: surface) { [weak self] outcome, suggestion in
            Task { await self?.proactiveEngine?.record(outcome, for: suggestion, now: Date()) }
        }

        proactiveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.proactiveTick() }
        }
        // A first look shortly after launch settles, so calendar offers don't wait a full minute.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            Task { @MainActor in await self?.proactiveTick() }
        }
    }

    /// Ask the engine for the single best suggestion and surface it — but only
    /// while Aria is idle, never on top of speech, a task, or a live conversation.
    @MainActor
    private func proactiveTick() async {
        guard let engine = proactiveEngine, let presenter = proactivePresenter else { return }
        guard idleForProactive, presenter.pending == nil else { return }
        guard let suggestion = await engine.tick(now: Date()) else { return }
        // An await elapsed — re-check we're still idle and nothing else surfaced.
        guard idleForProactive, presenter.pending == nil else { return }
        presenter.present(suggestion)
        scheduleProactiveExpiry(at: suggestion.expiry)
        Log.trace("proactive: surfaced \(suggestion.dedupeKey)")
    }

    /// Idle = not speaking, no running task, no active conversation, not mid-reveal.
    private var idleForProactive: Bool {
        !isSpeaking && !taskActive && !wakeEngine.conversationActive && !proactiveAwaitingReply
    }

    private func scheduleProactiveExpiry(at date: Date) {
        proactiveExpiryTimer?.invalidate()
        let delay = max(1, date.timeIntervalSinceNow)
        proactiveExpiryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.proactivePresenter,
                      p.pending != nil, !self.proactiveAwaitingReply else { return }
                p.expire(now: Date())
                Log.trace("proactive: suggestion expired untouched")
            }
        }
    }

    /// Called when the user wakes Aria while a suggestion is glowing — speak it
    /// and await their yes/no.
    @MainActor
    private func revealPendingSuggestionIfAny() {
        guard let p = proactivePresenter, p.pending != nil, !proactiveAwaitingReply else { return }
        proactiveAwaitingReply = true
        proactiveExpiryTimer?.invalidate()
        p.reveal()
    }

    /// Speak a line, then re-arm the mic for the user's reply (mirrors the chat
    /// turn tail). Used to voice a revealed offer and accept confirmations.
    @MainActor
    func speakAndListen(_ line: String) {
        wakeEngine.isSuspended = true
        isSpeaking = true
        speechStartedAt = Date()
        applyVoiceSettings()
        islandViewModel.appendResponse(line)
        streamVoice.onAllFinished = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.wakeEngine.freshTurn()
            self.wakeEngine.isSuspended = false
            self.islandViewModel.beginListening()
            self.convSilenceTimer?.invalidate()
            self.convSilenceTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.conversationSilenceTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.session?.end() }
            }
        }
        streamVoice.enqueue(line)
        if !streamVoice.isSpeaking { streamVoice.onAllFinished?() }
    }

    /// Run an accepted suggestion's command through the normal voice pipeline.
    @MainActor
    func runProactiveCommand(_ command: String) { handleCommand(command) }

    /// Approve an accepted learned routine and confirm out loud.
    @MainActor
    func approveProactivePattern(_ id: UUID) async {
        await patternEngine.approve(id, mode: .previewFirst)
        speakAndListen("Done — I'll take care of that automatically from now on.")
    }

    /// Compose today's briefing, save it as a note, and (for the scheduled
    /// agent) notify. Returns (briefing text, ok).
    @discardableResult
    private func deliverBriefing(silent: Bool) async -> (String, Bool) {
        let (text, ok) = await BriefingComposer.compose(gemini: orchestrator.geminiClient)
        let title = "Briefing — \(Date().formatted(date: .abbreviated, time: .omitted))"
        _ = try? await SaveNoteTool().run(input: ["title": title, "content": text])
        if silent {
            Notifier.notify(title: "Your briefing is ready",
                            body: String(text.prefix(140)))
        }
        return (text, ok)
    }

    /// Pull calendar events starting within `window` seconds. Returns nothing
    /// unless calendar access is already granted (never prompts from a timer).
    nonisolated private static func upcomingCalendarEvents(now: Date, window: TimeInterval) async -> [UpcomingEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(window), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .map { UpcomingEvent(id: $0.eventIdentifier ?? ($0.title ?? UUID().uuidString),
                                 title: $0.title ?? "an event",
                                 start: $0.startDate) }
    }

    /// Route the orchestrator's confirmation requests (run destructive code,
    /// save a generated tool) to a modal alert.
    private func configureConfirmation() {
        Task {
            await orchestrator.setConfirmationHandler { prompt in
                await MainActor.run { Self.confirm(prompt) }
            }
            // Plan preview (V10): for bigger foreground tasks, speak the plan
            // and wait for a spoken/typed go-ahead before executing.
            await orchestrator.setPlanApprovalHandler { [weak self] steps in
                await self?.previewPlanAndAwaitApproval(steps) ?? true
            }
        }
    }

    /// Speak a short plan summary and wait for yes/no. Modes (Settings):
    /// auto = preview only multi-step plans (default), always, never.
    /// No reply within 20s = proceed — the user asked for the task.
    @MainActor
    private func previewPlanAndAwaitApproval(_ steps: [TaskStep]) async -> Bool {
        let mode = UserDefaults.standard.string(forKey: "app.planPreview") ?? "auto"
        switch mode {
        case "never": return true
        case "always": break
        default: if steps.count < 4 { return true }     // auto
        }
        let summary = steps.prefix(4).enumerated()
            .map { "\($0.offset + 1). \($0.element.summary)" }
            .joined(separator: ", ")
        let extra = steps.count > 4 ? ", and \(steps.count - 4) more" : ""
        let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            planDecision = cont
            planDecisionTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.resolvePlanDecision(true) }   // silence = go
            }
            speakAndListen("Here's my plan: \(summary)\(extra). Should I go ahead?")
        }
        return approved
    }

    @MainActor
    private func resolvePlanDecision(_ approved: Bool) {
        planDecisionTimer?.invalidate(); planDecisionTimer = nil
        planDecision?.resume(returning: approved)
        planDecision = nil
    }

    @MainActor
    private static func confirm(_ message: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Aria"
        alert.informativeText = message
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Panel

    private func setupPanel() {
        let panel = IslandPanel()
        let host = NSHostingView(rootView: IslandView(viewModel: islandViewModel))
        host.frame = panel.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel

        islandViewModel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.setPanelVisible(visible)
            // Re-arm wake only when the pill is hidden AND Aria isn't still
            // speaking — otherwise a long spoken reply could re-trigger her.
            if !visible && !self.isSpeaking {
                self.wakeEngine.isSuspended = false
                Log.trace("island hidden → wake re-armed (isSuspended=false)")
            }
        }

        // Task panel — floats top-right while an autonomous task is running.
        taskPanel = TaskPanel(viewModel: taskViewModel)
        taskViewModel.onVisibilityChange = { [weak self] visible in
            guard let p = self?.taskPanel else { return }
            if visible { p.reposition(); p.orderFrontRegardless() } else { p.orderOut(nil) }
        }
        taskViewModel.onStop = { [weak self] in
            guard let self else { return }
            self.taskActive = false
            self.streamVoice.stop()             // silence queued narration immediately
            self.currentTurnTask?.cancel()      // engine checks isCancelled before next step
            self.isSpeaking = false
            self.wakeEngine.freshTurn()
            self.wakeEngine.isSuspended = false // re-arm the mic — never leave Aria deaf
            self.islandViewModel.dismiss()
            self.taskViewModel.hide()
        }
    }

    private func setPanelVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible {
            panel.reposition()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Engine wiring

    private func applyConversationSettings() {
        // sensitivity 0…1 (1 = most sensitive) → lower RMS threshold + shorter onset.
        let s = AppSettings.shared.bargeInSensitivity
        let threshold = 1800.0 - s * 1500.0      // ~1800 (needs loud) … ~300 (touchy)
        let onset = Int((4.0 - s * 2.0).rounded()) // 4 frames (40 ms) … 2 frames (20 ms)
        bargeController.configure(onsetFrames: onset, energyThreshold: threshold)
        refreshSpeakerGate()
    }

    /// Wire (or unwire) the experimental speaker gate. verifyWake is only set when the
    /// gate is active (enrolling, or enabled + enrolled) so the wake path is untouched
    /// by default — accept() itself always allows when inert.
    private func refreshSpeakerGate() {
        speakerGate.enabled = AppSettings.shared.speakerVerificationEnabled
        wakeEngine.verifyWake = speakerGate.isActive ? { [weak self] f in self?.speakerGate.accept(f) ?? true } : nil
    }

    /// Capture the next few "Hey Aria" utterances as the owner's voiceprint.
    func enrollOwnerVoice() {
        speakerGate.onEnrollmentComplete = { [weak self] in
            self?.refreshSpeakerGate()
            self?.islandViewModel.beginListening()
        }
        speakerGate.beginEnrollment()
        refreshSpeakerGate()   // sets verifyWake so enrollment frames accumulate
    }

    private func applyVoiceSettings() {
        let s = AppSettings.shared
        voice.enabled = s.voiceEnabled
        voice.geminiVoiceName = s.geminiVoiceName
    }

    private func wireEngine() {
        func refreshTheme() {
            islandViewModel.accent = AppSettings.shared.accentColor
            islandViewModel.glowColors = Theme.glowColors(id: AppSettings.shared.glowPaletteID,
                                                          accent: AppSettings.shared.accentColor)
        }
        refreshTheme()
        settingsCancellable = Publishers.MergeMany(
            AppSettings.shared.$accentChoiceRaw.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$glowPaletteID.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$bargeInSensitivity.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$speakerVerificationEnabled.map { _ in () }.eraseToAnyPublisher())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in refreshTheme(); self?.applyConversationSettings() }
        // The Settings "teach my voice" button posts this; enroll from live wakes.
        NotificationCenter.default.addObserver(forName: .ariaEnrollVoice, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.enrollOwnerVoice() }
        }
        // Computer-use: show the visible "controlling your Mac" indicator while ui_* runs.
        computerUseIndicator.onStop = { [weak self] in
            self?.currentTurnTask?.cancel()
            self?.taskActive = false
            self?.streamVoice.stop()
            self?.wakeEngine.isSuspended = false
        }
        NotificationCenter.default.addObserver(forName: .ariaUIActivity, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.computerUseIndicator.pulse() }
        }
        // Quiet update check on launch (surfaces in Settings → General).
        Task { await UpdateChecker.shared.check() }
        applyVoiceSettings()
        applyConversationSettings()
        voice.audioBus = audioBus
        voice.onStart = { [weak self] in
            self?.isSpeaking = true
            self?.wakeEngine.isSuspended = true
        }
        voice.onFinish = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            // If the pill already hid while Aria was talking, re-arm wake now.
            if !self.islandViewModel.isVisible { self.wakeEngine.isSuspended = false }
        }
        streamVoice = StreamingVoice(speakChunk: { [weak self] in self?.voice.speakChunk($0) },
                                     stopAll: { [weak self] in self?.voice.stop() })
        voice.onChunkFinished = { [weak self] in self?.streamVoice.chunkDidFinish() }
        wakeEngine.onWake = { [weak self] in
            guard let self else { return }
            Log.trace("onWake — conversation start")
            self.wakeEngine.conversationActive = true
            self.session = ConversationSession(
                onEnd: { [weak self] in self?.endConversation() },
                onTurn: { [weak self] in self?.handleCommand($0) })
            self.session?.start()
            self.islandViewModel.beginListening()
            self.playChime(.wake)   // soft "I'm listening" cue
            // If a suggestion is glowing, lead with it and await the user's yes/no.
            self.revealPendingSuggestionIfAny()
        }
        wakeEngine.onAudioLevel = { [weak self] level in
            self?.islandViewModel.updateAudioLevel(level)
        }
        wakeEngine.onCommand = { [weak self] command in
            Log.trace("onCommand: '\(command)'")
            self?.convSilenceTimer?.invalidate()      // user engaged; cancel end timer
            self?.session?.userSaid(command)
        }
        wakeEngine.onCommandEmpty = { [weak self] in
            // Heard the wake word but no command — dismiss only if still listening.
            guard let self, self.islandViewModel.state == .listening else { return }
            self.islandViewModel.dismiss()
        }
        wakeEngine.onError = { [weak self] message in
            self?.islandViewModel.beginListening()
            self?.islandViewModel.showError(message)
        }
        // v5.1 talk-over barge-in. AudioBus feeds the CLEANED mic stream to the
        // recognizer (audio thread → nonisolated acceptCleanedFrame) and to the
        // BargeController, which watches its energy while Aria speaks. On talk-over
        // it stops her and re-arms to capture what you say.
        // These run on the AUDIO thread — capture the consumers directly so we never
        // read a main-actor-isolated property (self.wakeEngine/…) off the main actor,
        // which traps in release builds. acceptCleanedFrame/feed/setPlaying are all
        // nonisolated + internally locked, so calling them from the audio thread is safe.
        let wake = wakeEngine
        let barge = bargeController
        audioBus.onCleanedFrame = { frame in
            wake.acceptCleanedFrame(frame)
            barge.feed(frame)
        }
        audioBus.onPlayStateChange = { playing in
            barge.setPlaying(playing)
        }
        bargeController.onBarge = { [weak self] in
            Task { @MainActor in self?.handleBarge() }
        }
    }

    // MARK: Barge-in

    @MainActor private func handleBarge() {
        guard AppSettings.shared.bargeInEnabled, isSpeaking else { return }
        // Grace at the start of her speech: the AEC needs a moment to converge, so
        // ignore the first ~400 ms to avoid a residual-echo false barge.
        guard Date().timeIntervalSince(speechStartedAt) > 0.4 else { return }
        Log.trace("barge-in — user talked over Aria")
        streamVoice.stop()              // → AudioBus.stopPlayback()
        currentTurnTask?.cancel()
        taskActive = false
        isSpeaking = false
        convSilenceTimer?.invalidate()
        // Re-arm into command capture so the interrupting utterance becomes the next
        // turn (she stopped the instant you spoke; now she listens).
        wakeEngine.freshTurn()
        wakeEngine.isSuspended = false
        islandViewModel.beginListening()
    }

    private func startListening() {
        Task {
            let micOK = await PermissionsManager.requestMicrophone()
            let speechOK = await PermissionsManager.requestSpeech()
            Log.trace("permissions: mic=\(micOK) speech=\(speechOK)")
            guard micOK, speechOK else {
                let missing = [micOK ? nil : "Microphone", speechOK ? nil : "Speech Recognition"]
                    .compactMap { $0 }.joined(separator: " + ")
                Log.app.error("Permissions denied: \(missing)")
                islandViewModel.beginListening()
                islandViewModel.showError("\(missing) permission denied. Enable it in System Settings → Privacy & Security, then relaunch Aria.")
                return
            }
            do {
                try audioBus.start()          // owns the mic; feeds cleaned frames to the wake engine
                try wakeEngine.start()
                Log.trace("audio bus + wake engine started OK — listening for 'Hey Aria'")
            }
            catch {
                Log.trace("audio/wake start FAILED: \(error.localizedDescription)")
                Log.app.error("Audio/wake engine failed to start: \(error.localizedDescription)")
                islandViewModel.beginListening()
                islandViewModel.showError(error.localizedDescription)
            }
        }
    }

    // MARK: Command handling

    private func handleCommand(_ command: String) {
        let lower = command.lowercased()

        // Answering a plan preview? Affirmative → execute; anything else →
        // cancel the task (an explicit different request becomes the next turn).
        if planDecision != nil {
            let yes = ProactiveReply.isAffirmative(command)
            resolvePlanDecision(yes)
            if yes { return }
            let negatives = ["no", "nope", "stop", "cancel", "don't", "never mind", "nah"]
            if negatives.contains(where: lower.contains) { return }
            // Not yes, not an explicit no — treat as a brand-new request.
        }

        // Answering a revealed proactive offer? Yes → run it; anything else →
        // dismiss the offer and treat the words as a normal request.
        if proactiveAwaitingReply {
            proactiveAwaitingReply = false
            let action = proactivePresenter?.pending?.action
            if ProactiveReply.isAffirmative(command) {
                Task { [weak self] in await self?.proactivePresenter?.accept(now: Date()) }
                if case .acknowledge = action { streamVoice.stop(); session?.end() }
                return   // acknowledge/runCommand/approve handle their own follow-up
            }
            proactivePresenter?.dismiss(now: Date())
            // fall through — process `command` as an ordinary turn
        }

        if lower.contains("dismiss") || lower.contains("thanks aria") || lower.contains("never mind") {
            streamVoice.stop(); session?.end(); return
        }

        // "Brief me" — the signature daily-briefing workflow, on demand.
        if BriefingComposer.isBriefingIntent(command) {
            islandViewModel.beginThinking()
            playChime(.task)
            currentTurnTask = Task { [weak self] in
                guard let self else { return }
                let (text, _) = await self.deliverBriefing(silent: false)
                await MainActor.run {
                    self.islandViewModel.appendResponse(text)
                    self.speakAndListen(text)
                }
            }
            return
        }

        // Resume the interrupted task. resumeTask() reports "nothing to resume" itself
        // if there isn't one, so no async pre-check is needed on the main actor here.
        if ResumeIntent.matches(command) {
            runAutonomousTask(command, resume: true)
            return
        }

        if IntentRouter.isTask(command) {
            runAutonomousTask(command)
            return
        }

        wakeEngine.isSuspended = true
        isSpeaking = true
        speechStartedAt = Date()
        applyVoiceSettings()
        islandViewModel.beginThinking()
        // The Gemini voice speaks the whole reply in ONE call at the end — per-
        // sentence TTS calls burn the free quota fast.
        streamVoice.onAllFinished = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            // Fresh recognition session so Aria's own voice (heard by the mic while
            // she spoke) doesn't leak into the next turn, then resume listening.
            self.wakeEngine.freshTurn()
            self.wakeEngine.isSuspended = false
            self.islandViewModel.beginListening()   // show "Listening…" for a follow-up
            self.convSilenceTimer?.invalidate()
            self.convSilenceTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.conversationSilenceTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.session?.end() }
            }
        }
        currentTurnTask = Task { [weak self] in
            guard let self else { return }
            await self.orchestrator.handleStreaming(command: command, privacyMode: AppSettings.shared.privacyMode) { delta in
                Task { @MainActor [weak self] in
                    self?.islandViewModel.appendResponse(delta)   // caption streams; no auto-dismiss
                }
            }
            await MainActor.run {
                if Task.isCancelled { return }   // barge-in cancelled this turn — don't resume speaking
                // Speak the whole reply in a single Gemini call.
                let full = self.islandViewModel.responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !full.isEmpty { self.streamVoice.enqueue(full) }
                // Safety: if nothing was spoken (empty reply/error), re-arm anyway.
                if !self.streamVoice.isSpeaking { self.streamVoice.onAllFinished?() }
            }
        }
    }

    private func runAutonomousTask(_ goal: String, resume: Bool = false) {
        taskActive = true
        playChime(.task)   // "rolling up sleeves" — a longer job is starting
        wakeEngine.isSuspended = true
        isSpeaking = true
        speechStartedAt = Date()
        islandViewModel.beginThinking()
        applyVoiceSettings()

        // The voice queue drains several times during a task (after the spoken plan,
        // between steps). Only re-arm wake once the task is DONE (taskActive == false),
        // and re-arm exactly the way the chat path does — fresh turn + silence timer
        // that ends the session through the canonical endConversation() reset.
        streamVoice.onAllFinished = { [weak self] in
            guard let self, !self.taskActive else { return }
            self.isSpeaking = false
            self.wakeEngine.freshTurn()
            self.wakeEngine.isSuspended = false
            self.islandViewModel.beginListening()
            self.convSilenceTimer?.invalidate()
            self.convSilenceTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.conversationSilenceTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.session?.end() }
            }
        }

        currentTurnTask = Task { [weak self] in
            guard let self else { return }
            let handler: @Sendable (TaskEvent) -> Void = { event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .planReady(let plan):
                        self.taskViewModel.show(plan)
                    case .stepStarted(let i):
                        self.taskViewModel.markRunning(i)
                        // Spoken play-by-play: a short "Searching the web…" as each step
                        // begins. The plan-start narrate already gave the overview, so skip
                        // the first step to avoid repeating it.
                        if i > 0, AppSettings.shared.spokenStepNarration,
                           let steps = self.taskViewModel.plan?.steps, steps.indices.contains(i) {
                            let line = TaskNarration.spoken(for: steps[i].summary)
                            if !line.isEmpty { self.streamVoice.enqueue(line) }
                        }
                    case .stepFinished(let i, let ok, let result):
                        self.taskViewModel.markFinished(i, ok: ok, result: result)
                    case .narrate(let line):
                        self.islandViewModel.appendResponse(line + " ")
                        self.streamVoice.enqueue(line)
                    case .finished(let ok, let summary):
                        self.taskActive = false   // now the next queue-drain re-arms wake
                        self.playChime(ok ? .done : .error)
                        // Project memory: every finished task is recallable later.
                        Task { await WorkJournal.shared.record(kind: .task, title: goal,
                                                               outcome: summary, ok: ok) }
                        self.streamVoice.enqueue(summary)
                        if !self.streamVoice.isSpeaking { self.streamVoice.onAllFinished?() }
                        let finishedGoal = goal
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            await MainActor.run {
                                guard let self, self.taskViewModel.plan?.goal == finishedGoal else { return }
                                self.taskViewModel.hide()
                            }
                        }
                    }
                }
            }
            if resume {
                await self.orchestrator.resumeTask(emit: handler)
            } else {
                await self.orchestrator.runTask(goal: goal, emit: handler)
            }
        }
    }

    private func endConversation() {
        convSilenceTimer?.invalidate(); convSilenceTimer = nil
        // Drop the ended session: ConversationSession.userSaid silently ignores
        // input after end(), so keeping the dead object made the SECOND typed
        // command vanish ("she only answers once") — found live.
        session = nil
        // A revealed-but-unanswered offer expires (not counted as a rejection).
        if proactiveAwaitingReply {
            proactiveAwaitingReply = false
            proactivePresenter?.expire(now: Date())
        }
        wakeEngine.endConversation()
        islandViewModel.dismiss()
    }

    func toggleManually() {
        if islandViewModel.isVisible {
            islandViewModel.dismiss()
        } else {
            islandViewModel.beginListening()
        }
    }
}

/// Bridges the testable `SuggestionPresenter` to the live orb, voice, and
/// orchestrator. Holds the controller weakly to avoid a retain cycle.
@MainActor
private final class ProactiveSurfaceAdapter: PresenterSurface {
    weak var controller: AriaController?
    init(controller: AriaController) { self.controller = controller }

    func showGlow() { controller?.islandViewModel.showSuggestionGlow() }
    func clearGlow() { controller?.islandViewModel.clearSuggestionGlow() }
    func speak(_ line: String) { controller?.speakAndListen(line) }
    func runCommand(_ command: String) async { controller?.runProactiveCommand(command) }
    func approvePattern(_ id: UUID) async { await controller?.approveProactivePattern(id) }
}
