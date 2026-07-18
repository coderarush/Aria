import AppKit
import SwiftUI

/// NSHostingView that lets a click reach its SwiftUI controls even when the host
/// panel isn't the key window. Without this, the first click on the Stop button in
/// a non-activating accessory-app panel is swallowed by window activation instead
/// of firing the button.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating panel hosting the task checklist, positioned top-right of the main screen.
final class TaskPanel: NSPanel {
    init(viewModel: TaskViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        // Above the full-screen island glow overlay (which sits at .statusBar), so
        // nothing can sit over the Stop button.
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        contentView = FirstMouseHostingView(rootView: TaskPanelView(viewModel: viewModel))
    }

    override var canBecomeKey: Bool { true }

    func reposition() {
        guard let s = NSScreen.main else { return }
        setFrameOrigin(NSPoint(
            x: s.visibleFrame.maxX - frame.width - 24,
            y: s.visibleFrame.maxY - frame.height - 24))
    }
}
