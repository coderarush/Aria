import Foundation
import ApplicationServices
import AppKit

/// One actionable on-screen control, read from the accessibility tree.
struct UIElement: Equatable {
    let role: String        // AXButton, AXTextField, …
    let label: String       // title / description / role-description
    let value: String       // current value (for fields)
    let frame: CGRect       // screen position + size
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

/// Reads the frontmost app's Accessibility tree — Aria's "eyes." Deterministic and
/// free (no model). Needs the Accessibility permission (System Settings → Privacy &
/// Security → Accessibility). Apps it can't read (some Electron/canvas) fall back to
/// vision (VisionLocator) later.
enum AXReader {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func frontmostAppName() -> String {
        frontmostTarget()?.localizedName ?? "the app"
    }

    /// The app to operate on: the frontmost app that ISN'T Aria itself (so reading the
    /// UI tree targets the user's app, never our own panels).
    static func frontmostTarget() -> NSRunningApplication? {
        let ws = NSWorkspace.shared
        let me = Bundle.main.bundleIdentifier
        if let f = ws.frontmostApplication, f.bundleIdentifier != me { return f }
        return ws.runningApplications.first { $0.isActive && $0.bundleIdentifier != me } ?? ws.frontmostApplication
    }

    /// Score how well an element label matches a query: exact > prefix > contains.
    static func matchScore(label: String, query: String) -> Int {
        let l = label.lowercased(), q = query.lowercased()
        guard !l.isEmpty, !q.isEmpty else { return 0 }
        if l == q { return 100 }
        if l.hasPrefix(q) { return 80 }
        if q.hasPrefix(l) { return 70 }
        if l.contains(q) { return 50 }
        if q.contains(l) { return 30 }
        return 0
    }

    /// Prompt for the Accessibility permission (opens the system dialog once).
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static let actionableRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXMenuItem", "AXMenuButton",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXLink", "AXComboBox",
        "AXSlider", "AXTabGroup", "AXDisclosureTriangle", "AXCell", "AXRow"
    ]
    static func isActionable(role: String) -> Bool { actionableRoles.contains(role) }

    /// Can we type into the currently-focused element? Used to verify a text field is
    /// actually focused BEFORE typing — otherwise keystrokes vanish into nothing and we'd
    /// falsely report success. `role` is the AX role with or without the "AX" prefix.
    /// Permissive for unknown roles (e.g. web areas) so we never block legitimate typing.
    static func canTypeInto(focusedRole role: String) -> Bool {
        let r = role.replacingOccurrences(of: "AX", with: "")
        let editable: Set<String> = ["TextField", "TextArea", "ComboBox", "SearchField", "SecureTextField"]
        if editable.contains(r) { return true }
        // Clearly non-text targets (or nothing focused: "") → can't type here.
        let blocked: Set<String> = ["", "Button", "Link", "CheckBox", "RadioButton", "MenuItem",
                                    "MenuButton", "PopUpButton", "Image", "StaticText", "Slider",
                                    "Cell", "Row", "Tab", "DisclosureTriangle", "Group", "Heading"]
        if blocked.contains(r) { return false }
        return true   // unknown role — allow rather than block real typing
    }

    /// Pick the most useful human label from the available attributes.
    static func bestLabel(title: String, description: String, roleDescription: String, value: String) -> String {
        for c in [title, description, value, roleDescription] where !c.trimmingCharacters(in: .whitespaces).isEmpty {
            return c.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// A numbered, model-readable summary of the elements.
    static func summarize(_ els: [UIElement]) -> String {
        guard !els.isEmpty else { return "(no readable controls — the app may need the vision fallback)" }
        return els.prefix(60).enumerated().map { i, e in
            let v = e.value.isEmpty ? "" : " = “\(e.value.prefix(40))”"
            return "\(i + 1). [\(e.role.replacingOccurrences(of: "AX", with: ""))] \(e.label)\(v)"
        }.joined(separator: "\n")
    }

    /// Read actionable controls of the frontmost app.
    static func readFrontmost(limit: Int = 200) -> [UIElement] {
        guard hasPermission, let app = frontmostTarget() else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var out: [UIElement] = []
        walk(axApp, into: &out, limit: limit, depth: 0)
        return out
    }

    /// Find the live AX element best matching a label (+ optional role), by score.
    static func find(role: String?, label: String) -> AXUIElement? {
        guard hasPermission, let app = frontmostTarget() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var best: (el: AXUIElement, score: Int)?
        findWalk(axApp, role: role, want: label, best: &best, depth: 0)
        return best?.el
    }

    // MARK: tree walking

    private static func walk(_ el: AXUIElement, into out: inout [UIElement], limit: Int, depth: Int) {
        if out.count >= limit || depth > 30 { return }
        let role = str(el, kAXRoleAttribute)
        if isActionable(role: role) {
            let label = bestLabel(title: str(el, kAXTitleAttribute),
                                  description: str(el, kAXDescriptionAttribute),
                                  roleDescription: str(el, kAXRoleDescriptionAttribute),
                                  value: str(el, kAXValueAttribute))
            if !label.isEmpty {
                out.append(UIElement(role: role, label: label, value: str(el, kAXValueAttribute), frame: frame(el)))
            }
        }
        for c in children(el) { walk(c, into: &out, limit: limit, depth: depth + 1) }
    }

    private static func findWalk(_ el: AXUIElement, role: String?, want: String,
                                 best: inout (el: AXUIElement, score: Int)?, depth: Int) {
        if depth > 30 || (best?.score ?? 0) >= 100 { return }   // 100 = exact match, can't beat it
        let r = str(el, kAXRoleAttribute)
        if isActionable(role: r), role == nil || r == role {
            let label = bestLabel(title: str(el, kAXTitleAttribute),
                                  description: str(el, kAXDescriptionAttribute),
                                  roleDescription: str(el, kAXRoleDescriptionAttribute),
                                  value: str(el, kAXValueAttribute))
            let sc = matchScore(label: label, query: want)
            if sc > 0, sc > (best?.score ?? 0) { best = (el, sc) }
        }
        for c in children(el) { findWalk(c, role: role, want: want, best: &best, depth: depth + 1) }
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private static func str(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private static func frame(_ el: AXUIElement) -> CGRect {
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
        return CGRect(origin: pos, size: size)
    }
}
