import CoreGraphics
import Foundation

/// Pure geometry for the Lens — Aria's "circle anything on screen and ask" overlay.
/// Kept free of SwiftUI/AppKit so the math (bounding box of a freehand lasso, where
/// to spawn the trailing blobs, screen→fraction conversion) is deterministic and
/// unit-tested. The view layer turns these numbers into gooey ink.
enum LensGeometry {

    /// Axis-aligned bounding box of a freehand stroke, optionally inflated by
    /// `padding` on every side. Empty/❶-point strokes return `.null`.
    static func boundingBox(of points: [CGPoint], padding: CGFloat = 0) -> CGRect {
        guard points.count >= 2 else { return .null }
        var minX = points[0].x, minY = points[0].y
        var maxX = points[0].x, maxY = points[0].y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return r.insetBy(dx: -padding, dy: -padding)
    }

    /// Clamp a rect to lie fully inside `bounds` (e.g. the screen). Never returns
    /// a negative-sized rect; a rect entirely outside collapses to a zero-size
    /// rect on the nearest edge.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX, bounds.minX), bounds.maxX)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY)
        let maxX = min(max(rect.maxX, bounds.minX), bounds.maxX)
        let maxY = min(max(rect.maxY, bounds.minY), bounds.maxY)
        return CGRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
    }

    /// Total path length of a polyline (sum of segment lengths).
    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    /// Whether a stroke reads as a closed loop (a circle/lasso) rather than an
    /// open scribble or line: the gap between first and last point is small
    /// relative to the stroke's overall span. Used to decide "circled a thing"
    /// vs "drew a line under a thing" — both are valid, this just informs intent.
    static func isClosedLoop(_ points: [CGPoint], tolerance: CGFloat = 0.22) -> Bool {
        guard points.count >= 8 else { return false }
        let box = boundingBox(of: points)
        let span = max(box.width, box.height)
        guard span > 1 else { return false }
        let gap = hypot(points[0].x - points[points.count - 1].x,
                        points[0].y - points[points.count - 1].y)
        return gap <= span * tolerance
    }

    /// Resample a stroke to `count` points spaced ~evenly by arc length. Used to
    /// place the small trailing blobs so they don't bunch up where the user drew
    /// slowly. Degenerate inputs are returned as-is (never crashes/empties).
    static func sampleAlong(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count >= 1, points.count >= 2 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return Array(repeating: points[0], count: count) }
        let step = total / CGFloat(count)
        var out: [CGPoint] = []
        var target = step / 2          // first sample at half-step (centered)
        var walked: CGFloat = 0
        var i = 1
        while out.count < count && i < points.count {
            let a = points[i - 1], b = points[i]
            let segLen = hypot(b.x - a.x, b.y - a.y)
            if segLen <= 0 { i += 1; continue }
            while target <= walked + segLen && out.count < count {
                let t = (target - walked) / segLen
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                target += step
            }
            walked += segLen
            i += 1
        }
        // Floating-point shortfall: pad with the last point.
        while out.count < count { out.append(points[points.count - 1]) }
        return out
    }

    /// Convert a screen-space rect into normalized fractions (0…1, top-left
    /// origin) of `screenSize` — the shape a multimodal model wants when told
    /// "the user circled this part of the screenshot". Clamped to [0,1].
    static func fractionRect(_ rect: CGRect, in screenSize: CGSize) -> CGRect {
        guard screenSize.width > 0, screenSize.height > 0 else { return .zero }
        let x = clamp01(rect.minX / screenSize.width)
        let y = clamp01(rect.minY / screenSize.height)
        let w = clamp01(rect.width / screenSize.width)
        let h = clamp01(rect.height / screenSize.height)
        return CGRect(x: x, y: y, width: min(w, 1 - x), height: min(h, 1 - y))
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
}
