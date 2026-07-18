import AppKit
import Combine
import SwiftUI

/// Owns the passive, click-through overlay that renders `AriaStage` — Aria's
/// guidance markers and worker swarm drawn directly on your screen. Always
/// click-through (it never intercepts your input); shown only while the stage has
/// something to draw, so an idle Aria does zero work here.
@MainActor
final class AriaStageController {
    private var panel: NSPanel?
    private let stage = AriaStage.shared
    private var cancellable: AnyCancellable?
    private var accent: Color

    init(accent: Color) {
        self.accent = accent
    }

    private var screenObserver: NSObjectProtocol?

    func start() {
        // React to stage changes on the main actor; show/hide the panel to match.
        cancellable = stage.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sync() }
        // Re-fit the overlay (and re-render at the new size) if the display
        // arrangement or resolution changes mid-session.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel,
                      let screen = NSScreen.main ?? NSScreen.screens.first else { return }
                panel.setFrame(screen.frame, display: true)
                self.rebuildContent()
            }
        }
        sync()
    }

    func setAccent(_ color: Color) {
        accent = color
        if panel != nil { rebuildContent() }
    }

    private func sync() {
        if stage.isActive {
            ensurePanel()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true            // always click-through
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovable = false
        p.hidesOnDeactivate = false
        panel = p
        rebuildContent()
    }

    private func rebuildContent() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.contentView = NSHostingView(
            rootView: AriaStageView(stage: stage, accent: accent, screenSize: screen.frame.size))
    }

    func stop() {
        cancellable?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        panel?.orderOut(nil)
        panel = nil
    }
}
