import AppKit
import SwiftUI

/// AppKit host for the full Aria app window (v1). Mirrors how `AppDelegate`
/// hosts the Settings window: a single, reused titled/resizable `NSWindow`
/// wrapping an `NSHostingView(rootView: AppWindowView())`.
///
/// Aria runs as an accessory app (`LSUIElement`), so — like the Settings and
/// onboarding windows — we flip the activation policy to `.regular` and activate
/// before fronting, otherwise the window won't surface.
@MainActor
final class AppWindowController {
    private var window: NSWindow?

    /// Show the app window, creating it once and reusing it thereafter.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "Aria"
            win.contentView = NSHostingView(rootView: AppWindowView())
            win.isReleasedWhenClosed = false       // reuse the single instance
            win.setContentSize(NSSize(width: 1000, height: 680))
            win.minSize = NSSize(width: 880, height: 560)
            win.center()
            window = win
        }

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
