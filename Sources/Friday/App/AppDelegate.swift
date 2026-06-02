import AppKit

/// Sets up the menu-bar status item and owns the FridayController. The app has
/// `LSUIElement = true`, so there is no Dock icon — the ⬡ menu-bar item is the
/// only chrome.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let controller = FridayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Friday launching")
        migrateAPIKeyIfNeeded()
        setupStatusItem()
        controller.start()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⬡"
        item.button?.toolTip = "Friday"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Summon Friday", action: #selector(summon), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Friday", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func summon() { controller.toggleManually() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: API key migration

    /// One-time migration: if a key sits in ~/Friday/.apikey and the Keychain is
    /// empty, move it into the Keychain.
    private func migrateAPIKeyIfNeeded() {
        guard KeychainManager.read(account: KeychainKey.geminiAPIKey) == nil else { return }
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Friday/.apikey")
        guard let raw = try? String(contentsOf: legacy, encoding: .utf8) else { return }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainManager.save(key, account: KeychainKey.geminiAPIKey)
            Log.app.info("Migrated Gemini API key from ~/Friday/.apikey to Keychain")
        } catch {
            Log.app.error("API key migration failed: \(error.localizedDescription)")
        }
    }
}
