import Foundation
import ApplicationServices
import CoreGraphics

/// Aria's "hands": clicks, types, and presses keys in the frontmost app via the
/// Accessibility actions (AXPress) where possible, falling back to synthetic mouse/
/// keyboard events (CGEvent). Needs the Accessibility permission.
enum UIActuator {
    /// Click an element by label (+ optional role). Tries AXPress, else clicks center.
    static func click(role: String?, label: String) -> Bool {
        guard let el = AXReader.find(role: role, label: label) else { return false }
        if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { return true }
        clickAt(center(of: el))
        return true
    }

    /// Outcome of a confidence-gated click attempt.
    enum ClickOutcome: Equatable {
        case clicked                 // we acted
        case unsure(label: String)   // located something, but too low-confidence to click blindly
        case notFound                // couldn't locate at all
    }

    /// Locate a target FRESH (AX first, vision fallback) and attach a confidence. Called
    /// on every attempt — including retries — so a moved UI is re-resolved rather than
    /// clicked at a stale rect. `nil` means we couldn't find it at all.
    ///
    /// AX path is synchronous + MainActor-friendly; the vision fallback is async and only
    /// runs when AX misses, so ordinary clicks never pay for a screenshot.
    static func resolveTarget(role: String?, label: String) async -> ResolvedTarget? {
        // AX read + geometry are nonisolated static helpers (same as `click` uses); only the
        // vision fallback is async.
        if let hit = AXReader.findScored(role: role, label: label) {
            return ResolvedTarget(point: center(of: hit.el), confidence: .fromAX(matchScore: hit.score))
        }
        if let v = await VisionLocator.locateScored(label) {
            return ResolvedTarget(point: v.point, confidence: .fromVision(score: v.confidence))
        }
        return nil
    }

    /// Confidence-gated click: re-resolve the target, and only fire the click if the
    /// targeting decision says `.act`. Below threshold we DON'T click a guess — we report
    /// `.unsure` so the caller can ask the user to confirm instead of clicking blindly.
    static func clickConfident(role: String?, label: String,
                               threshold: Double = OperatorTargeting.actThreshold) async -> ClickOutcome {
        guard let target = await resolveTarget(role: role, label: label) else { return .notFound }
        switch OperatorTargeting.decide(target.confidence, threshold: threshold) {
        case .act:
            clickAt(target.point)
            return .clicked
        case .askFirst, .abort:
            return .unsure(label: label)
        }
    }

    static func clickAt(_ p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Synthetic right-click (secondary button) at a point — pops the context menu.
    static func rightClickAt(_ p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: p, mouseButton: .right)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right)?.post(tap: .cghidEventTap)
    }

    /// Right-click a control by label to open its context menu. Tries the
    /// Accessibility "show menu" action first (clean, no cursor jump), else
    /// falls back to a synthetic right-click at the element's center.
    static func rightClick(role: String?, label: String) -> Bool {
        guard let el = AXReader.find(role: role, label: label) else { return false }
        if AXUIElementPerformAction(el, kAXShowMenuAction as CFString) == .success { return true }
        rightClickAt(center(of: el))
        return true
    }

    // MARK: Menu-bar traversal (P4 — menus are 20-30% of Mac workflows)

    /// Parse a human menu path ("Format > Font > Bold", "View → Zoom → In") into
    /// its components, tolerating extra whitespace and stray separators.
    static func menuPath(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == ">" || $0 == "→" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Match a queried menu title against an actual item title, case-insensitively
    /// and tolerating a trailing ellipsis ("Export…" matches "Export").
    static func menuTitleMatches(itemTitle: String, query: String) -> Bool {
        let t = itemTitle.lowercased().trimmingCharacters(in: .whitespaces)
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !q.isEmpty else { return false }
        if t == q { return true }
        let stripped = t.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped == q
    }

    /// Walk the frontmost app's menu bar along `components` and press the leaf.
    /// e.g. menuPath("Format > Font > Bold"). Returns false if any step is missing.
    static func clickMenuPath(_ components: [String]) -> Bool {
        guard !components.isEmpty, let app = AXReader.frontmostTarget() else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        var container = raw as! AXUIElement
        for (i, title) in components.enumerated() {
            guard let item = menuItems(of: container).first(where: {
                menuTitleMatches(itemTitle: axString($0, kAXTitleAttribute as String), query: title)
            }) else { return false }
            if i == components.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            // Open the submenu, then descend (its AXMenu child is flattened next round).
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            container = item
        }
        return false
    }

    /// Children of a menu container, flattening a single AXMenu wrapper so a
    /// menu-bar item's items and a submenu's items read uniformly.
    private static func menuItems(of el: AXUIElement) -> [AXUIElement] {
        var out: [AXUIElement] = []
        for child in axChildren(el) {
            if axString(child, kAXRoleAttribute as String) == "AXMenu" {
                out.append(contentsOf: axChildren(child))
            } else {
                out.append(child)
            }
        }
        return out
    }

    private static func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let arr = ref as? [AXUIElement] else { return [] }
        return arr
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return "" }
        return (ref as? String) ?? ""
    }

    /// Scroll the area under the pointer (pixels; +dy scrolls down content up).
    static func scroll(dx: Int, dy: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    /// Type arbitrary text into the focused field (Unicode, no keycodes needed).
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var ch = UniChar(scalar.value)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Press a key combo like "cmd+s", "enter", "cmd+shift+z". Returns false if the
    /// key isn't recognized.
    static func key(_ combo: String) -> Bool {
        let parts = combo.lowercased().split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " }).map(String.init)
        guard let keyName = parts.last, let code = Self.keyCodes[keyName] else { return false }
        var flags: CGEventFlags = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default: break
            }
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        return true
    }

    // MARK: helpers

    private static func center(of el: AXUIElement) -> CGPoint {
        var posV: CFTypeRef?, sizeV: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posV) == .success,
           let point = AXGeometry.point(from: posV) {
            pos = point
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeV) == .success,
           let parsed = AXGeometry.size(from: sizeV) {
            size = parsed
        }
        return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    }

    /// US-layout virtual keycodes for the common keys Aria needs.
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
        "comma": 43, "period": 47, "slash": 44
    ]
}
