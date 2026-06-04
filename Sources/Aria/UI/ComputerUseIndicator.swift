import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the ui_* tools each time Aria acts on screen, so a visible indicator
    /// shows the user she's in control and they can Stop.
    static let ariaUIActivity = Notification.Name("AriaUIActivity")
}

/// A small always-on-top pill — "Aria is controlling your Mac" + Stop — shown while
/// computer-use actions run and auto-hidden a few seconds after the last one. The
/// honest, visible signal that the agent is driving the machine.
@MainActor
final class ComputerUseIndicator {
    private var panel: NSPanel?
    private var hideTimer: Timer?
    var onStop: (() -> Void)?

    /// Call on each UI action: show (if hidden) and push back the auto-hide.
    func pulse() {
        show()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 46),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .popUpMenu
            p.isFloatingPanel = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = FirstMouseHostingView(rootView: ComputerUseIndicatorView(
                onStop: { [weak self] in self?.onStop?(); self?.hide() }))
            panel = p
        }
        if let s = NSScreen.main {
            panel?.setFrameOrigin(NSPoint(x: s.visibleFrame.midX - 170, y: s.visibleFrame.maxY - 64))
        }
        panel?.orderFrontRegardless()
    }
}

struct ComputerUseIndicatorView: View {
    var onStop: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays").foregroundStyle(.white)
            Text("Aria is controlling your Mac")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Button("Stop") { onStop() }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(width: 340, height: 46)
        .background(.black.opacity(0.85), in: Capsule())
    }
}
