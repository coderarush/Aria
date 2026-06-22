import AppKit
import SwiftUI

/// Hosts the Lens overlay: a full-screen, **interactive** panel (unlike the
/// passive `IslandPanel`) that captures the user's drag so they can circle or
/// draw on whatever is beneath. On completion it hands back the bounding box of
/// the circled region in top-left screen points — the exact shape
/// `ScreenCaptureEngine.captureRegionJPEG` wants — and tears itself down so the
/// screenshot it triggers is clean (no scrim, no ink).
@MainActor
final class LensOverlayController {
    private var panel: LensPanel?
    private var keyMonitor: Any?
    private let session: LensSession

    /// Called with (stroke points, bounding box in top-left screen points, screen
    /// size in points) when the user finishes circling in explain mode.
    var onExplain: (([CGPoint], CGRect, CGSize) -> Void)?
    /// Called when the user cancels (Esc, or a bare tap with no circle).
    var onCancel: (() -> Void)?

    init(mode: LensSession.Mode, accent: Color, glow: [Color]) {
        self.session = LensSession(mode: mode, accent: accent, glow: glow)
    }

    func present() {
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenSize = screen.frame.size

        let view = LensCanvasView(
            session: session,
            onComplete: { [weak self] points in
                guard let self else { return }
                let bbox = LensGeometry.clamp(
                    LensGeometry.boundingBox(of: points, padding: 14),
                    to: CGRect(origin: .zero, size: screenSize))
                self.onExplain?(points, bbox, screenSize)
            },
            onCancel: { [weak self] in self?.onCancel?() })

        let panel = LensPanel(contentRect: screen.frame)
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        // Esc cancels; ⏎ finishes a draw-mode session. Local monitor (the panel is
        // key) — consume so the keystroke doesn't leak to the app beneath.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:  // Escape
                self.onCancel?()
                return nil
            case 36 where self.session.mode == .draw:  // Return ends a drawing session
                self.onCancel?()
                return nil
            default:
                return event
            }
        }
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// A borderless panel that *can* become key (so it receives the drag + Esc),
    /// floats above all spaces, and never activates the app's main window chrome.
    final class LensPanel: NSPanel {
        init(contentRect: NSRect) {
            super.init(contentRect: contentRect,
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
            isFloatingPanel = true
            level = .statusBar
            backgroundColor = .clear
            isOpaque = false
            hasShadow = false
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            isMovable = false
            hidesOnDeactivate = false
            ignoresMouseEvents = false
        }
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}
