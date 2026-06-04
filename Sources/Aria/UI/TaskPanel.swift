import AppKit
import SwiftUI

/// Floating panel hosting the task checklist, positioned top-right of the main screen.
final class TaskPanel: NSPanel {
    init(viewModel: TaskViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: TaskPanelView(viewModel: viewModel))
    }

    override var canBecomeKey: Bool { true }

    func reposition() {
        guard let s = NSScreen.main else { return }
        setFrameOrigin(NSPoint(
            x: s.visibleFrame.maxX - frame.width - 24,
            y: s.visibleFrame.maxY - frame.height - 24))
    }
}
