import Foundation
import ApplicationServices
import AppKit

/// Aria's ambient awareness — a cheap, always-available read of what the user is
/// looking at *right now*. Only lightweight Accessibility attributes (focused window
/// title, focused field role, selected text); no screenshot, no model call, no
/// continuous polling — captured once per turn when she's invoked. This lets deictic
/// commands ("summarize this", "reply to her", "translate the selection") resolve
/// without the user describing their screen. macOS hides secure fields from the AX
/// selection attribute, so passwords never leak in here.
struct ScreenContext: Equatable {
    var windowTitle: String = ""
    var focusedRole: String = ""   // human form, e.g. "TextField", "WebArea"
    var selectedText: String = ""

    /// Capture the current ambient context. Returns empty fields when Accessibility
    /// isn't granted or nothing is focused. @MainActor because it touches AppKit/AX.
    @MainActor static func snapshot() -> ScreenContext {
        guard AXReader.hasPermission, let app = AXReader.frontmostTarget() else { return ScreenContext() }
        var ctx = ScreenContext()

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let win = element(axApp, kAXFocusedWindowAttribute) {
            ctx.windowTitle = string(win, kAXTitleAttribute)
        }

        // System-wide focused element → selected text + role (works across apps).
        let sys = AXUIElementCreateSystemWide()
        if let focused = element(sys, kAXFocusedUIElementAttribute) {
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
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
        return (v as? String) ?? ""
    }
}
