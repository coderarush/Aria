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
    private var learningTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    /// True while Aria is speaking; keeps wake suspended even if the pill
    /// auto-hides mid-utterance, so she can't hear herself and re-trigger.
    private var isSpeaking = false

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
        wakeEngine.onWake = { [weak self] in
            Log.trace("onWake — island listening")
            self?.islandViewModel.beginListening()
        }
        wakeEngine.onAudioLevel = { [weak self] level in
            self?.islandViewModel.updateAudioLevel(level)
        }
        wakeEngine.onCommand = { [weak self] command in
            Log.trace("onCommand fired: '\(command)'")
            self?.handleCommand(command)
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
        // Dismissal phrases.
        let lower = command.lowercased()
        if lower.contains("dismiss") || lower.contains("thanks aria") || lower.contains("never mind") {
            voice.stop()
            islandViewModel.dismiss()
            return
        }

        // Stop listening for new wakes while we work, so a stray "aria" can't
        // interrupt or dismiss the island mid-task. Resumed when the island hides
        // (see onVisibilityChange in setupPanel).
        wakeEngine.isSuspended = true
        islandViewModel.beginThinking()
        let privacy = AppSettings.shared.privacyMode
        Log.trace("handleCommand: '\(command)' privacy=\(privacy) — thinking")
        Task {
            await patternEngine.recordCommand(command)
            Log.trace("calling orchestrator.handle")
            let response = await orchestrator.handle(command: command, privacyMode: privacy)
            Log.trace("orchestrator returned: type=\(response.type.rawValue) conf=\(response.confidence) msg=\(response.message.prefix(120))")
            if response.confidence == 0 {
                islandViewModel.showError(response.message)
            } else {
                islandViewModel.showResponse(response.message)
                applyVoiceSettings()
                voice.speak(response.message)
            }
            Log.trace("island updated, state=\(String(describing: islandViewModel.state))")
        }
    }

    func toggleManually() {
        if islandViewModel.isVisible {
            islandViewModel.dismiss()
        } else {
            islandViewModel.beginListening()
        }
    }
}
