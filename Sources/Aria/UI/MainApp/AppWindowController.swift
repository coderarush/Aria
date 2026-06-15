import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the main window's Settings item. The host app (or this controller
    /// as a fallback) opens the existing SettingsView in response — keeping the
    /// settings UI as the single source of truth (no duplication here).
    static let ariaOpenSettings = Notification.Name("aria.openSettings")
}

/// Hosts Aria's premium main window. A single, reused, centered window with a
/// unified title-bar so the materials sidebar runs edge to edge. Created lazily
/// and kept alive across closes.
@MainActor
final class AppWindowController {
    static let shared = AppWindowController()

    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsObserver: NSObjectProtocol?

    private init() {
        // If nothing else handles the Settings request, fall back to showing the
        // existing SettingsView ourselves so the button always works.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .ariaOpenSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showSettingsFallback() }
        }
    }

    /// Show (creating if needed) the main window and bring it forward.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Aria"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: AppWindowView())
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AriaMainWindow")
        window.center()
        return window
    }

    /// Last-resort Settings presenter — used only if the host app isn't already
    /// observing `.ariaOpenSettings`. Reuses the real SettingsView verbatim.
    private func showSettingsFallback() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Aria Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
}
