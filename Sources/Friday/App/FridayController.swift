import SwiftUI
import AppKit

/// Top-level coordinator that owns the runtime engines and the orb panel, and
/// wires wake → listen → think → respond. Lives for the app's lifetime.
@MainActor
final class FridayController {

    let orbViewModel = OrbViewModel()
    private let wakeEngine = WakeWordEngine()
    private let orchestrator = AgentOrchestrator()
    private let patternEngine = PatternEngine()
    private var panel: OrbPanel?
    private var learningTimer: Timer?

    func start() {
        setupPanel()
        wireEngine()
        configureConfirmation()
        configureLearning()
        startListening()
    }

    private var previewWindow: NSWindow?

    /// Preview mode (used for screenshots/docs): shows the orb in a plain titled
    /// window on a dark backdrop, without starting the mic so there is no TCC
    /// prompt. The production orb lives in a borderless non-activating panel,
    /// which doesn't capture cleanly; this window does. Triggered by the
    /// `/tmp/friday_show_orb` sentinel or the `FRIDAY_SHOW_ORB` env var.
    func startForScreenshot() {
        // Defer off the launch call stack so the runloop is up before building
        // the Metal-backed hosting view.
        DispatchQueue.main.async { [weak self] in self?.buildPreviewWindow() }
    }

    private func buildPreviewWindow() {
        orbViewModel.beginListening()
        orbViewModel.updateAudioLevel(0.6)

        let root = ZStack {
            Color.black
            OrbView(viewModel: orbViewModel)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Friday — Orb Preview"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        previewWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Publish the window number so a screenshot script can target it.
        try? "\(window.windowNumber)".write(toFile: "/tmp/friday_window.txt", atomically: true, encoding: .utf8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.orbViewModel.showResponse("**Friday** is online.\nSay *Hey Friday* to begin.")
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
                orbViewModel.beginThinking()
                let response = await orchestrator.handle(command: command)
                orbViewModel.showResponse("⚡️ " + response.message)
            }
        }
    }

    @MainActor
    private func presentSuggestion(_ pattern: BehaviorPattern) {
        orbViewModel.beginListening()
        orbViewModel.showResponse(pattern.description + " — want me to handle that automatically?")
        let approved = Self.confirm("\(pattern.description).\n\nWant Friday to do this automatically from now on?")
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
        alert.messageText = "Friday"
        alert.informativeText = message
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Panel

    private func setupPanel() {
        let panel = OrbPanel()
        let host = NSHostingView(rootView: OrbView(viewModel: orbViewModel))
        host.frame = panel.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel

        orbViewModel.onVisibilityChange = { [weak self] visible in
            self?.setPanelVisible(visible)
        }
    }

    private func setPanelVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible {
            positionPanel(panel)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        // Bottom-center.
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Engine wiring

    private func wireEngine() {
        wakeEngine.onWake = { [weak self] in
            self?.orbViewModel.beginListening()
        }
        wakeEngine.onAudioLevel = { [weak self] level in
            self?.orbViewModel.updateAudioLevel(level)
        }
        wakeEngine.onCommand = { [weak self] command in
            self?.handleCommand(command)
        }
        wakeEngine.onError = { [weak self] message in
            self?.orbViewModel.beginListening()
            self?.orbViewModel.showError(message)
        }
    }

    private func startListening() {
        Task {
            let micOK = await PermissionsManager.requestMicrophone()
            let speechOK = await PermissionsManager.requestSpeech()
            guard micOK, speechOK else {
                let missing = [micOK ? nil : "Microphone", speechOK ? nil : "Speech Recognition"]
                    .compactMap { $0 }.joined(separator: " + ")
                Log.app.error("Permissions denied: \(missing)")
                orbViewModel.beginListening()
                orbViewModel.showError("\(missing) permission denied. Enable it in System Settings → Privacy & Security, then relaunch Friday.")
                return
            }
            do { try wakeEngine.start() }
            catch {
                Log.app.error("Wake engine failed to start: \(error.localizedDescription)")
                orbViewModel.beginListening()
                orbViewModel.showError(error.localizedDescription)
            }
        }
    }

    // MARK: Command handling

    private func handleCommand(_ command: String) {
        // Dismissal phrases.
        let lower = command.lowercased()
        if lower.contains("dismiss") || lower.contains("thanks friday") || lower.contains("never mind") {
            orbViewModel.dismiss()
            return
        }

        orbViewModel.beginThinking()
        let privacy = AppSettings.shared.privacyMode
        Task {
            await patternEngine.recordCommand(command)
            let response = await orchestrator.handle(command: command, privacyMode: privacy)
            if response.confidence == 0 {
                orbViewModel.showError(response.message)
            } else {
                orbViewModel.showResponse(response.message)
            }
        }
    }

    func toggleManually() {
        if orbViewModel.isVisible {
            orbViewModel.dismiss()
        } else {
            orbViewModel.beginListening()
        }
    }
}

/// Borderless, floating, non-activating panel that hosts the orb across all
/// spaces without stealing focus from the user's current app.
final class OrbPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
