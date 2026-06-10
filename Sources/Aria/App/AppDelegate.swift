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
        // ALWAYS start listening immediately — never leave Aria dead waiting on the
        // onboarding window (which, as an accessory app, may not even surface). On a
        // fresh install the mic prompt fires now; onboarding then explains it. A working
        // assistant beats perfect prompt ordering.
        startControllerOnce()
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
        NSApp.setActivationPolicy(.regular)   // accessory apps won't surface a window otherwise
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.blobStatusImage()
        item.button?.toolTip = "Aria"

        let menu = NSMenu()
        let summonItem = NSMenuItem(title: "Talk to Aria", action: #selector(summon), keyEquivalent: " ")
        summonItem.keyEquivalentModifierMask = [.option]
        menu.addItem(summonItem)
        let typeItem = NSMenuItem(title: "Type to Aria…", action: #selector(typeToAria), keyEquivalent: " ")
        typeItem.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(typeItem)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Aria", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    /// Aria's blob as the menu bar icon — same layered-sine outline as the orb
    /// and the website. A template image, so macOS renders it ink-black on a
    /// light menu bar and white on a dark one.
    private static func blobStatusImage() -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let n = 11
            var pts: [CGPoint] = []
            for i in 0..<n {
                let a = CGFloat(i)
                let w = 0.6 * sin(0.6 + a * 0.9) + 0.3 * sin(1.02 + a * 1.7) + 0.1 * sin(0.3 + a * 2.3)
                let r = size * 0.42 * (1 + 0.10 * w)
                let ang = 2 * .pi * a / CGFloat(n) - .pi / 2
                pts.append(CGPoint(x: size / 2 + cos(ang) * r, y: size / 2 + sin(ang) * r))
            }
            let path = NSBezierPath()
            func pt(_ i: Int) -> CGPoint { pts[((i % n) + n) % n] }
            path.move(to: pt(0))
            for i in 0..<n {
                let p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2)
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
            }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func summon() { controller.summonAria() }
    @objc private func typeToAria() { controller.showTypePanel() }
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
        // One-shot, and NEVER on the main thread at launch: the first Keychain
        // access after a re-sign can block for minutes on the ACL check — this
        // single call was the "Aria takes 1-2 minutes to come alive" hang.
        let flag = "app.apikeyMigrationDone"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        DispatchQueue.global(qos: .utility).async {
            defer { UserDefaults.standard.set(true, forKey: flag) }
            Self.migrateAPIKeyNow()
        }
    }

    nonisolated private static func migrateAPIKeyNow() {
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
