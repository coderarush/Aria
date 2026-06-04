import SwiftUI
import AppKit
import AVFoundation
import Combine

/// Top-level coordinator that owns the runtime engines and the Island panel, and
/// wires wake → listen → think → respond. Lives for the app's lifetime.
@MainActor
final class AriaController {

    let islandViewModel = IslandViewModel()
    private let wakeEngine = WakeWordEngine()
    private let voice = VoiceEngine()
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
            self?.currentTurnTask?.cancel()
            self?.taskViewModel.hide()
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
        // sensitivity 0…1 (1 = most sensitive) → threshold ~0.20 (loud) … 0.04 (sensitive)
        let s = AppSettings.shared.bargeInSensitivity
        wakeEngine.bargeInThreshold = Float(0.20 - s * 0.16)
    }

    private func applyVoiceSettings() {
        let s = AppSettings.shared
        voice.enabled = s.voiceEnabled
        voice.voiceIdentifier = s.voiceIdentifier.isEmpty ? nil : s.voiceIdentifier
        voice.rate = Float(s.voiceRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) + AVSpeechUtteranceMinimumSpeechRate
        voice.kind = VoiceEngine.Kind(rawValue: s.voiceEngineKind) ?? .apple
        voice.geminiVoiceName = s.geminiVoiceName
    }

    private func wireEngine() {
        func refreshTheme() {
            islandViewModel.accent = AppSettings.shared.accentColor
            islandViewModel.glowColors = Theme.glowColors(id: AppSettings.shared.glowPaletteID,
                                                          accent: AppSettings.shared.accentColor)
        }
        refreshTheme()
        settingsCancellable = Publishers.Merge(
            AppSettings.shared.$accentChoiceRaw.map { _ in () },
            AppSettings.shared.$glowPaletteID.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { _ in refreshTheme() }
        applyVoiceSettings()
        applyConversationSettings()
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
        // Barge-in (talk-over) is disabled: it requires echo cancellation, which
        // breaks recognition on this hardware. Without AEC the mic hears Aria's own
        // voice and would false-trigger, so we don't wire onSpeechOnset. The model
        // is continuous follow-up: wait for her to finish, then talk (no re-wake).
    }

    // MARK: Barge-in

    private func handleBargeIn() {
        guard AppSettings.shared.bargeInEnabled else { return }
        guard isSpeaking else { return }                                    // only while she's talking
        guard Date().timeIntervalSince(speechStartedAt) > 0.5 else { return } // arm-grace
        Log.trace("barge-in — user interrupted")
        streamVoice.stop()                  // stop TTS + clear queue
        currentTurnTask?.cancel()           // cancel the in-flight stream
        isSpeaking = false
        convSilenceTimer?.invalidate()
        wakeEngine.isSuspended = false      // capture the user's interrupting utterance
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
                try wakeEngine.start()
                Log.trace("wake engine started OK — listening for 'Hey Aria'")
            }
            catch {
                Log.trace("wake engine start FAILED: \(error.localizedDescription)")
                Log.app.error("Wake engine failed to start: \(error.localizedDescription)")
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

        if IntentRouter.isTask(command) {
            runAutonomousTask(command)
            return
        }

        wakeEngine.isSuspended = true
        isSpeaking = true
        speechStartedAt = Date()
        applyVoiceSettings()
        islandViewModel.beginThinking()
        // Apple voice streams per sentence (instant). The Gemini cloud voice speaks
        // the whole reply in ONE call at the end — per-sentence Gemini calls burn
        // quota fast and fall back to the robotic Apple voice.
        let streamPerSentence = AppSettings.shared.voiceEngineKind != "gemini"
        var chunker = SentenceChunker()
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
                    guard let self else { return }
                    self.islandViewModel.appendResponse(delta)   // caption streams; no auto-dismiss
                    if streamPerSentence {
                        for chunk in chunker.push(delta) { self.streamVoice.enqueue(chunk) }
                    }
                }
            }
            await MainActor.run {
                if Task.isCancelled { return }   // barge-in cancelled this turn — don't resume speaking
                if streamPerSentence {
                    let tail = chunker.flush()
                    if !tail.isEmpty { self.streamVoice.enqueue(tail) }
                } else {
                    // Gemini voice: speak the whole reply in a single call.
                    let full = self.islandViewModel.responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !full.isEmpty { self.streamVoice.enqueue(full) }
                }
                // Safety: if nothing was spoken (empty reply/error), re-arm anyway.
                if !self.streamVoice.isSpeaking { self.streamVoice.onAllFinished?() }
            }
        }
    }

    private func runAutonomousTask(_ goal: String) {
        wakeEngine.isSuspended = true
        isSpeaking = true
        speechStartedAt = Date()
        islandViewModel.beginThinking()
        applyVoiceSettings()

        streamVoice.onAllFinished = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.wakeEngine.freshTurn()
            self.wakeEngine.isSuspended = false
            self.islandViewModel.beginListening()
        }

        currentTurnTask = Task { [weak self] in
            guard let self else { return }
            await self.orchestrator.runTask(goal: goal) { event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .planReady(let plan):
                        self.taskViewModel.show(plan)
                    case .stepStarted(let i):
                        self.taskViewModel.markRunning(i)
                    case .stepFinished(let i, let ok, let result):
                        self.taskViewModel.markFinished(i, ok: ok, result: result)
                    case .narrate(let line):
                        self.islandViewModel.appendResponse(line + " ")
                        self.streamVoice.enqueue(line)
                    case .finished(_, let summary):
                        self.streamVoice.enqueue(summary)
                        if !self.streamVoice.isSpeaking { self.streamVoice.onAllFinished?() }
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            await MainActor.run { self?.taskViewModel.hide() }
                        }
                    }
                }
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
