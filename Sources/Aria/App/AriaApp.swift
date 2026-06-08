import SwiftUI

/// Entry point. LSUIElement (set in Info.plist) keeps Aria out of the Dock;
/// all UI is the menu-bar item plus the floating orb panel, both managed by
/// AppDelegate / AriaController. The empty Settings scene satisfies the
/// SwiftUI App requirement without showing a window.
///
/// Release builds MUST disable whole-module optimization (Package.swift / Makefile)
/// or tapping a SwiftUI control crashes in the runtime's executor-isolation check on
/// Swift 6.3 / macOS 26.3. See the README "release builds" note.
@main
struct AriaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
