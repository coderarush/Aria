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

    static func clickAt(_ p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
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
