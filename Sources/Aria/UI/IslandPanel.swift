import AppKit
import SwiftUI

/// Full-screen, click-through overlay panel hosting Aria's presence (border glow
/// + blob). It passes every mouse event through to the apps beneath EXCEPT while
/// the cursor is over the draggable blob, where it momentarily becomes
/// interactive so the drag gesture can move her. `ignoresMouseEvents` has a
/// single writer (`syncInteractivity`) so it can never get stuck "on".
final class IslandPanel: NSPanel {
    /// Blob frame in SwiftUI `.global` space; nil = fully click-through.
    private var blobFrame: CGRect?
    private var mouseMonitor: Any?

    init() {
        super.init(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true            // passive overlay — never blocks clicks
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Cover the whole main screen.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        setFrame(screen.frame, display: true)
    }

    /// Called by the SwiftUI layer with the live blob frame (nil when no blob is
    /// drawn). Installs a cheap mouse-moved monitor only while a blob exists.
    func setBlobFrame(_ rect: CGRect?) {
        blobFrame = rect
        if rect == nil {
            teardownMonitor()
            syncInteractivity(cursor: nil)        // → fully click-through
        } else {
            installMonitor()
            syncInteractivity(cursor: NSEvent.mouseLocation)
        }
    }

    private func installMonitor() {
        guard mouseMonitor == nil else { return }
        // Only `.mouseMoved` toggles interactivity — during an in-flight drag macOS
        // emits `.leftMouseDragged` (not moved), so the panel stays interactive
        // until the user releases and the next move re-syncs. No drag-state needed.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.syncInteractivity(cursor: NSEvent.mouseLocation)
        }
    }

    private func teardownMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    /// THE single writer of `ignoresMouseEvents`. Interactive only when a blob
    /// frame exists AND the cursor is inside it; click-through otherwise.
    private func syncInteractivity(cursor: CGPoint?) {
        guard let frame = blobFrame, let cursor else {
            if !ignoresMouseEvents { ignoresMouseEvents = true }
            return
        }
        let scr = screen?.frame ?? NSScreen.main?.frame ?? .zero
        let over = BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: frame, screen: scr, inflation: 12)
        if ignoresMouseEvents == over { ignoresMouseEvents = !over }
    }

    deinit { teardownMonitor() }
}
