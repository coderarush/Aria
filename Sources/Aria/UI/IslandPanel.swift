import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the Island pill at the top-center
/// of the main screen, hugging the notch. Floats above other windows; click-
/// through is toggled by the controller based on visibility.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position centered on the main screen, top edge pinned under the notch.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame, size: self.frame.size)
        setFrame(frame, display: true)
    }
}
