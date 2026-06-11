import Foundation
import UserNotifications

/// Native macOS notifications (UNUserNotificationCenter) with a graceful
/// AppleScript fallback. Native gives Aria real Notification Center presence —
/// grouping, the app's blob icon, Do-Not-Disturb respect — instead of the
/// Script Editor attribution the AppleScript hack shows.
///
/// Falls back automatically when running unbundled (`swift run` has no bundle
/// identifier, UNUserNotificationCenter throws) or when the user denied
/// notification permission.
enum Notifier {

    /// UNUserNotificationCenter requires a real app bundle.
    static var nativeAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private static var requested = false

    /// Post a notification. Safe from any thread/actor.
    static func notify(title: String, body: String) {
        guard nativeAvailable else {
            fallback(title: title, body: body)
            return
        }
        let center = UNUserNotificationCenter.current()
        if !requested {
            requested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request) { error in
            if error != nil {
                // Denied or unavailable — never drop the message silently.
                fallback(title: title, body: body)
            }
        }
    }

    private static func fallback(title: String, body: String) {
        Task { @MainActor in
            let t = AppleScriptTool.quotedLiteral(title)
            let b = AppleScriptTool.quotedLiteral(body)
            _ = AppleScriptTool.execute("display notification \"\(b)\" with title \"\(t)\"")
        }
    }
}
