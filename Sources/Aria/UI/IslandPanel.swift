import AppKit
import SwiftUI

/// Full-screen, click-through overlay panel hosting Aria's Siri-style glow.
/// Always passes mouse events through; floats above normal windows.
final class IslandPanel: NSPanel {
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
}
