import AppKit
import SwiftUI

/// Sets up the menu-bar status item and owns the AriaController. The app has
/// `LSUIElement = true`, so there is no Dock icon — the ⬡ menu-bar item is the
/// only chrome.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let controller = AriaController()
    private var onboardingWindow: NSWindow?
    private var didStart = false   // controller.start() must run exactly once

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Aria launching")
        Log.trace("=== Aria launched ===")
        NSSetUncaughtExceptionHandler { exception in
            Log.trace("UNCAUGHT EXCEPTION: \(exception.name.rawValue) — \(exception.reason ?? "?")\n\(exception.callStackSymbols.joined(separator: "\n"))")
        }
        // Preview mode — handled first so it never touches the Keychain (which
        // can block on first run after an ad-hoc re-sign).
        if ProcessInfo.processInfo.environment["ARIA_SHOW_ORB"] != nil
            || FileManager.default.fileExists(atPath: "/tmp/aria_show_orb") {
            setupStatusItem()
            controller.startForScreenshot()
            return
        }
        migrateAPIKeyIfNeeded()
        setupStatusItem()
        // On a fresh install, walk the user through permissions BEFORE starting audio
        // capture — otherwise the system mic prompt fires before the welcome explains
        // why, and the wake engine spins up without mic access. Start the controller
        // immediately on every later launch; on first launch, start it only once
        // onboarding finishes (see the onComplete callback below).
        if AppSettings.shared.onboardingComplete {
            startControllerOnce()
        }
        showOnboardingIfNeeded()
    }

    /// Start listening exactly once, regardless of path (normal launch, onboarding
    /// finished, or onboarding window dismissed).
    private func startControllerOnce() {
        guard !didStart else { return }
        didStart = true
        controller.start()
    }

    // MARK: Onboarding

    private func showOnboardingIfNeeded() {
        guard !AppSettings.shared.onboardingComplete else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.center()
        window.title = "Welcome to Aria"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView { [weak self] in
            AppSettings.shared.onboardingComplete = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            // Permissions are granted now — start listening for "Hey Aria".
            self?.startControllerOnce()
        })
        window.delegate = self   // catch a manual close (red X) so Aria still boots
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⬡"
        item.button?.toolTip = "Aria"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Summon Aria", action: #selector(summon), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Aria", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func summon() { controller.toggleManually() }
    @objc private func quit() { NSApp.terminate(nil) }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)   // ensure the window can come forward
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "Aria Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    // MARK: API key migration

    /// One-time migration: if a key sits in ~/Aria/.apikey and the Keychain is
    /// empty, move it into the Keychain.
    private func migrateAPIKeyIfNeeded() {
        guard KeychainManager.read(account: KeychainKey.geminiAPIKey) == nil else { return }
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Aria/.apikey")
        guard let raw = try? String(contentsOf: legacy, encoding: .utf8) else { return }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainManager.save(key, account: KeychainKey.geminiAPIKey)
            Log.app.info("Migrated Gemini API key from ~/Aria/.apikey to Keychain")
        } catch {
            Log.app.error("API key migration failed: \(error.localizedDescription)")
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    /// If the user dismisses the welcome window with the red X instead of finishing
    /// onboarding, still start listening so Aria isn't left running dead. Onboarding
    /// stays incomplete, so it will reappear on the next launch to collect permissions.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject === onboardingWindow else { return }
        startControllerOnce()
    }
}
