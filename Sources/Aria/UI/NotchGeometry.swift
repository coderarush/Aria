import Foundation
import CoreGraphics

/// Pure geometry for placing the Island pill at top-center / the notch.
/// Kept free of AppKit so it is unit-testable; the panel passes real
/// NSScreen values in at runtime.
enum NotchGeometry {
    /// Frame for the panel given the screen frame (bottom-left origin) and the
    /// desired pill size. The pill's TOP edge is pinned to the screen top so it
    /// grows downward as it expands; it is centered horizontally under the notch.
    static func panelFrame(screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A display has a notch when its top safe-area inset is non-zero.
    static func hasNotch(topInset: CGFloat) -> Bool { topInset > 0 }
}
