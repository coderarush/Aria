import Foundation
import AppKit
import ApplicationServices

/// Pure tiling math, separated so it's testable without Accessibility.
/// Frames are computed in Cocoa coordinates (origin bottom-left) inside the
/// screen's visible frame, then converted to the AX top-left convention.
enum WindowGeometry {

    enum Position: String, CaseIterable {
        case left, right, top, bottom, center, maximize
        case topLeft = "top-left", topRight = "top-right"
        case bottomLeft = "bottom-left", bottomRight = "bottom-right"

        /// Forgiving parse: "left half", "top right", "fullscreen", "middle"…
        static func parse(_ text: String) -> Position? {
            let t = text.lowercased()
                .replacingOccurrences(of: "half", with: "")
                .replacingOccurrences(of: "screen", with: "")
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
            switch t {
            case "left": return .left
            case "right": return .right
            case "top", "upper": return .top
            case "bottom", "lower": return .bottom
            case "center", "centre", "middle": return .center
            case "maximize", "maximise", "full", "max", "big": return .maximize
            case "topleft", "upperleft": return .topLeft
            case "topright", "upperright": return .topRight
            case "bottomleft", "lowerleft": return .bottomLeft
            case "bottomright", "lowerright": return .bottomRight
            default: return nil
            }
        }
    }

    /// Target frame (Cocoa coords) for a position within `visible`.
    static func frame(for position: Position, in visible: CGRect) -> CGRect {
        let w = visible.width, h = visible.height
        switch position {
        case .left:
            return CGRect(x: visible.minX, y: visible.minY, width: w / 2, height: h)
        case .right:
            return CGRect(x: visible.midX, y: visible.minY, width: w / 2, height: h)
        case .top:
            return CGRect(x: visible.minX, y: visible.midY, width: w, height: h / 2)
        case .bottom:
            return CGRect(x: visible.minX, y: visible.minY, width: w, height: h / 2)
        case .center:
            return CGRect(x: visible.minX + w * 0.125, y: visible.minY + h * 0.125,
                          width: w * 0.75, height: h * 0.75)
        case .maximize:
            return visible
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.midY, width: w / 2, height: h / 2)
        case .topRight:
            return CGRect(x: visible.midX, y: visible.midY, width: w / 2, height: h / 2)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: visible.minY, width: w / 2, height: h / 2)
        case .bottomRight:
            return CGRect(x: visible.midX, y: visible.minY, width: w / 2, height: h / 2)
        }
    }

    /// Cocoa rect (origin bottom-left) → AX point (origin top-left of the
    /// primary display) + size. `primaryHeight` is the FULL frame height of
    /// the primary screen.
    static func axPosition(for cocoaFrame: CGRect, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: cocoaFrame.minX,
                y: primaryHeight - cocoaFrame.maxY)
    }
}

/// "Put this window on the left half" / "tile Safari right" / "maximize this".
/// Uses the Accessibility trust Aria already holds for computer use.
struct WindowArrangeTool: AriaTool {
    static let name = "window_arrange"
    static let description = "Move/resize an app's front window: left, right, top, bottom, center, maximize, or a corner (top-left…). Input: {position: left|right|top|bottom|center|maximize|top-left|top-right|bottom-left|bottom-right, app: optional app name; omitted = frontmost app}."
    static let paramHints: [String: String] = [
        "position": "left | right | top | bottom | center | maximize | top-left | top-right | bottom-left | bottom-right",
        "app": "Optional app name (e.g. 'Safari'); omitted = the frontmost app"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let raw = input["position"],
              let position = WindowGeometry.Position.parse(raw) else {
            return .fail("Missing input: position (left, right, top, bottom, center, maximize, or a corner).")
        }
        let appName = input["app"]?.trimmingCharacters(in: .whitespaces)
        return await MainActor.run {
            Self.arrange(position: position, appName: appName)
        }
    }

    @MainActor
    private static func arrange(position: WindowGeometry.Position, appName: String?) -> ToolResult {
        guard AXIsProcessTrusted() else {
            return .fail("I need Accessibility access to move windows — System Settings → Privacy & Security → Accessibility.")
        }

        let app: NSRunningApplication?
        if let name = appName, !name.isEmpty {
            app = NSWorkspace.shared.runningApplications.first {
                $0.localizedName?.lowercased() == name.lowercased()
            } ?? NSWorkspace.shared.runningApplications.first {
                $0.localizedName?.lowercased().contains(name.lowercased()) == true
            }
        } else {
            app = NSWorkspace.shared.frontmostApplication
        }
        guard let app else {
            return .fail("Couldn't find a running app\(appName.map { " named “\($0)”" } ?? "").")
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)
        if err != .success {
            // Fall back to the first window (app running but not focused).
            var windowsValue: CFTypeRef?
            err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
            windowValue = (windowsValue as? [AXUIElement])?.first
        }
        guard err == .success, let windowRef = windowValue else {
            return .fail("\(app.localizedName ?? "That app") has no window I can move.")
        }
        let window = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)

        // Tile on the screen the window currently occupies (fallback: main).
        let screen = Self.screenContaining(window: window) ?? NSScreen.main
        guard let visible = screen?.visibleFrame,
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return .fail("No display found to arrange on.")
        }

        let target = WindowGeometry.frame(for: position, in: visible)
        var axPoint = WindowGeometry.axPosition(for: target, primaryHeight: primaryHeight)
        var axSize = CGSize(width: target.width, height: target.height)
        guard let pointValue = AXValueCreate(.cgPoint, &axPoint),
              let sizeValue = AXValueCreate(.cgSize, &axSize) else {
            return .fail("Couldn't build the window geometry.")
        }
        // Size → position → size: some apps clamp position by current size.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        return .ok("Moved \(app.localizedName ?? "the app")'s window to \(position.rawValue).")
    }

    @MainActor
    private static func screenContaining(window: AXUIElement) -> NSScreen? {
        var posValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              let point = AXGeometry.point(from: posValue),
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        // AX top-left → Cocoa point for screen hit-testing.
        let cocoaPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(cocoaPoint) }
    }
}
