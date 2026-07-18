import Foundation
import ApplicationServices
import AppKit

/// Aria's ambient awareness — a cheap read of what the user is looking at (focused window
/// title, focused field role, selected text). No screenshot, no model call.
///
/// CRITICAL: this must never block the main thread. AXUIElementCopyAttributeValue can hang
/// for seconds on a busy app (a browser building its AX tree, in particular). It used to run
/// on the main actor every turn, which froze the whole app — no response, no voice, no
/// re-arm, and a corrupted main executor that crashed the Settings window. So snapshot() is
/// now `nonisolated` (runs off-main, on the agent actor) and every AX element is given a
/// short messaging timeout so a slow app returns empty instead of hanging.
struct ScreenContext: Equatable {
    var windowTitle: String = ""
    var focusedRole: String = ""   // human form, e.g. "TextField", "WebArea"
    var selectedText: String = ""

    private static let axTimeout: Float = 0.2   // seconds — never wait longer on a slow app

    /// Read ambient context for the frontmost app (by pid). Safe to call off the main
    /// thread; bounded so it can't freeze a turn.
    static func snapshot(pid: pid_t) -> ScreenContext {
        guard AXReader.hasPermission else { return ScreenContext() }
        var ctx = ScreenContext()

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, axTimeout)
        if let win = element(axApp, kAXFocusedWindowAttribute) {
            AXUIElementSetMessagingTimeout(win, axTimeout)
            ctx.windowTitle = string(win, kAXTitleAttribute)
        }

        // System-wide focused element → selected text + role (works across apps).
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, axTimeout)
        if let focused = element(sys, kAXFocusedUIElementAttribute) {
            AXUIElementSetMessagingTimeout(focused, axTimeout)
            ctx.focusedRole = string(focused, kAXRoleAttribute).replacingOccurrences(of: "AX", with: "")
            ctx.selectedText = cap(string(focused, kAXSelectedTextAttribute), 1000)
        }
        return ctx
    }

    static func cap(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n)) + "…"
    }

    // MARK: AX helpers

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v else { return nil }
        return AXGeometry.element(from: v)
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
        return (v as? String) ?? ""
    }
}
