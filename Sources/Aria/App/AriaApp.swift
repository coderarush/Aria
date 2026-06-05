import SwiftUI

/// Entry point. LSUIElement (set in Info.plist) keeps Aria out of the Dock;
/// all UI is the menu-bar item plus the floating orb panel, both managed by
/// AppDelegate / AriaController. The empty Settings scene satisfies the
/// SwiftUI App requirement without showing a window.
@main
struct AriaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Swift 6 made the executor-isolation check trap when it can't confirm isolation,
        // which crashes inside SwiftUI's List/AttributeGraph layout (EXC_BAD_ACCESS in
        // swift_task_isMainExecutor). Restore the legacy non-trapping behavior. Mirrors
        // Info.plist's LSEnvironment for bundle launches; this also covers `swift run`.
        // The runtime reads this lazily on the first executor check, so setting it here —
        // before any view renders — takes effect.
        setenv("SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE", "legacy", 1)
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
