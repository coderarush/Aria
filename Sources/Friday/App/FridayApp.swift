import SwiftUI

/// Entry point. LSUIElement (set in Info.plist) keeps Friday out of the Dock;
/// all UI is the menu-bar item plus the floating orb panel, both managed by
/// AppDelegate / FridayController. The empty Settings scene satisfies the
/// SwiftUI App requirement without showing a window.
@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
