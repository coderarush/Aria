import CoreGraphics

/// Pure coordinate math for deciding whether the mouse is over the draggable
/// blob. The overlay panel is otherwise fully click-through; this is the single
/// predicate that flips it interactive, so it is unit-tested in isolation.
///
/// Two coordinate systems meet here:
///   • `cursorScreen` — AppKit `NSEvent.mouseLocation`: origin bottom-left, y-up.
///   • `blobFrameSwiftUI` — SwiftUI `.global` frame: origin top-left, y-down.
/// We map the cursor into SwiftUI space using the screen frame, then test the
/// inflated blob rect.
enum BlobHitRegion {
    static func contains(cursorScreen: CGPoint,
                         blobFrameSwiftUI: CGRect,
                         screen: CGRect,
                         inflation: CGFloat) -> Bool {
        let sx = cursorScreen.x - screen.minX
        let sy = screen.maxY - cursorScreen.y                // flip y-up → y-down
        let region = blobFrameSwiftUI.insetBy(dx: -inflation, dy: -inflation)
        return region.contains(CGPoint(x: sx, y: sy))
    }
}
