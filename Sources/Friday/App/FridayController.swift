import SwiftUI
import AppKit

/// Top-level coordinator that owns the runtime engines and the orb panel, and
/// wires wake → listen → think → respond. Lives for the app's lifetime.
@MainActor
final class FridayController {

    let orbViewModel = OrbViewModel()
    private let wakeEngine = WakeWordEngine()
    private let orchestrator = AgentOrchestrator()
    private var panel: OrbPanel?

    func start() {
        setupPanel()
        wireEngine()
        configureConfirmation()
        startListening()
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
        guard let screen = NSScreen.main else { return }
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
    }

    private func startListening() {
        Task {
            let ok = await PermissionsManager.requestCorePermissions()
            guard ok else {
                Log.app.error("Core permissions denied — wake word disabled")
                return
            }
            do { try wakeEngine.start() }
            catch { Log.app.error("Wake engine failed to start: \(error.localizedDescription)") }
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
        Task {
            let response = await orchestrator.handle(command: command)
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
