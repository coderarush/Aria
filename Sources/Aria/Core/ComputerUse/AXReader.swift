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
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "the app"
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
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var out: [UIElement] = []
        walk(axApp, into: &out, limit: limit, depth: 0)
        return out
    }

    /// Find the live AX element best matching a label (+ optional role) — for acting on.
    static func find(role: String?, label: String) -> AXUIElement? {
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let want = label.lowercased()
        var best: AXUIElement?
        findWalk(axApp, role: role, want: want, best: &best, depth: 0)
        return best
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

    private static func findWalk(_ el: AXUIElement, role: String?, want: String, best: inout AXUIElement?, depth: Int) {
        if best != nil || depth > 30 { return }
        let r = str(el, kAXRoleAttribute)
        if isActionable(role: r), role == nil || r == role {
            let label = bestLabel(title: str(el, kAXTitleAttribute),
                                  description: str(el, kAXDescriptionAttribute),
                                  roleDescription: str(el, kAXRoleDescriptionAttribute),
                                  value: str(el, kAXValueAttribute)).lowercased()
            if !label.isEmpty, label.contains(want) || want.contains(label) { best = el; return }
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
           let p = posV, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue((p as! AXValue), .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeV) == .success,
           let s = sizeV, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue((s as! AXValue), .cgSize, &size)
        }
        return CGRect(origin: pos, size: size)
    }
}
