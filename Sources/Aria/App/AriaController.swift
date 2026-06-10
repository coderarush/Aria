import SwiftUI
import AppKit
import Combine

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
        setupPanel()
        wireEngine()
        configureConfirmation()
        configureLearning()
        startListening()
        offerResumeIfPending()
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
            let escaped = AppleScriptTool.quotedLiteral(msg)
            _ = AppleScriptTool.execute("display notification \"\(escaped)\" with title \"Aria\"")
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
        Task {
            await patternEngine.setSuggestionHandler { [weak self] pattern in
                Task { @MainActor in self?.presentSuggestion(pattern) }
            }
        }
        // Hourly: re-detect, surface suggestions, fire approved automations.
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
        _ = await patternEngine.patternsToSuggest()
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

    @MainActor
    private func presentSuggestion(_ pattern: BehaviorPattern) {
        islandViewModel.beginListening()
        islandViewModel.showResponse(pattern.description + " — want me to handle that automatically?")
        let approved = Self.confirm("\(pattern.description).\n\nWant Aria to do this automatically from now on?")
        Task {
            if approved {
                await patternEngine.approve(pattern.id, mode: .previewFirst)
            } else {
                await patternEngine.deferSuggestion(pattern.id)
            }
        }
    }

    /// Route the orchestrator's confirmation requests (run destructive code,
    /// save a generated tool) to a modal alert.
    private func configureConfirmation() {
        Task {
            await orchestrator.setConfirmationHandler { prompt in
                await MainActor.run { Self.confirm(prompt) }
            }
        }
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
        if lower.contains("dismiss") || lower.contains("thanks aria") || lower.contains("never mind") {
            streamVoice.stop(); session?.end(); return
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
                    case .finished(_, let summary):
                        self.taskActive = false   // now the next queue-drain re-arms wake
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
