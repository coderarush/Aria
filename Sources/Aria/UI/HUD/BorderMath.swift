import CoreGraphics
import Foundation

/// Pure geometry for the screen-edge presence. The border is an inset rounded
/// rectangle hugging the display; a brighter "comet" travels around it. Keeping
/// the math here (not in the view) makes the choreography unit-testable.
///
/// Parameter `u ∈ [0,1)` walks the perimeter clockwise (screen coords, y-down)
/// starting from top-center, so `u = 0.5` is bottom-center by symmetry — the
/// point the splash ignites from and the consolidate drains toward.
enum BorderMath {

    /// One straight or curved piece of the perimeter, tagged with its cumulative
    /// start length so a length can be located without re-walking from zero.
    private struct Inset {
        let rect: CGRect
        let r: CGFloat
        let topHalf: CGFloat      // W/2 - r
        let side: CGFloat         // H - 2r
        let bottom: CGFloat       // W - 2r
        let arc: CGFloat          // (π/2) r
        let total: CGFloat

        init(rect: CGRect, cornerRadius: CGFloat) {
            self.rect = rect
            // Clamp radius so it never exceeds half the smaller side.
            self.r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
            self.topHalf = rect.width / 2 - r
            self.side = rect.height - 2 * r
            self.bottom = rect.width - 2 * r
            self.arc = .pi / 2 * r
            // top-right-half + arc + right + arc + bottom + arc + left + arc + top-left-half
            self.total = topHalf + arc + side + arc + bottom + arc + side + arc + topHalf
        }
    }

    /// Point at parameter `u` plus the outward-normal angle (radians, in screen
    /// coords where +x is right and +y is down).
    static func point(u: Double, in rect: CGRect, cornerRadius: CGFloat) -> (point: CGPoint, normal: Double) {
        let g = Inset(rect: rect, cornerRadius: cornerRadius)
        guard g.total > 0 else { return (CGPoint(x: rect.midX, y: rect.midY), 0) }
        let s = CGFloat(u - floor(u)) * g.total
        return locate(s: s, g: g)
    }

    /// Perimeter parameter of the edge point nearest an interior point — where
    /// the consolidate animation drains to and the wake sweep begins.
    static func nearestU(to p: CGPoint, in rect: CGRect, cornerRadius: CGFloat) -> Double {
        let g = Inset(rect: rect, cornerRadius: cornerRadius)
        guard g.total > 0 else { return 0 }
        let samples = 1440
        var bestU = 0.0
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in 0..<samples {
            let u = Double(i) / Double(samples)
            let pt = locate(s: CGFloat(u) * g.total, g: g).point
            let dx = pt.x - p.x, dy = pt.y - p.y
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; bestU = u }
        }
        return bestU
    }

    /// Comet brightness at `u` for a head at `head` trailing `tail` length behind
    /// (all in `u` units, wrapping at 1.0). 1 at the head, smoothstep down to 0 at
    /// the tail end, 0 elsewhere.
    static func cometIntensity(u: Double, head: Double, tail: Double) -> Double {
        guard tail > 0 else { return 0 }
        // Distance *behind* the head (the comet trails the direction of travel).
        var d = head - u
        d -= floor(d)                    // wrap into [0,1)
        if d > tail { return 0 }
        let x = 1 - d / tail              // 1 at head → 0 at tail end
        return x * x * (3 - 2 * x)        // smoothstep
    }

    // MARK: - Perimeter walk

    private static func locate(s: CGFloat, g: Inset) -> (point: CGPoint, normal: Double) {
        let R = g.rect
        let r = g.r
        var rem = s

        // 1. top edge, right half: (midX, minY) → (maxX - r, minY); outward up
        if rem <= g.topHalf {
            return (CGPoint(x: R.midX + rem, y: R.minY), -.pi / 2)
        }
        rem -= g.topHalf

        // 2. top-right corner: center (maxX - r, minY + r), -90° → 0°
        if rem <= g.arc {
            let a = -Double.pi / 2 + Double(rem / g.arc) * (.pi / 2)
            return cornerPoint(cx: R.maxX - r, cy: R.minY + r, r: r, angle: a)
        }
        rem -= g.arc

        // 3. right edge: (maxX, minY + r) → (maxX, maxY - r); outward right
        if rem <= g.side {
            return (CGPoint(x: R.maxX, y: R.minY + r + rem), 0)
        }
        rem -= g.side

        // 4. bottom-right corner: center (maxX - r, maxY - r), 0° → 90°
        if rem <= g.arc {
            let a = Double(rem / g.arc) * (.pi / 2)
            return cornerPoint(cx: R.maxX - r, cy: R.maxY - r, r: r, angle: a)
        }
        rem -= g.arc

        // 5. bottom edge: (maxX - r, maxY) → (minX + r, maxY); outward down
        if rem <= g.bottom {
            return (CGPoint(x: R.maxX - r - rem, y: R.maxY), .pi / 2)
        }
        rem -= g.bottom

        // 6. bottom-left corner: center (minX + r, maxY - r), 90° → 180°
        if rem <= g.arc {
            let a = Double.pi / 2 + Double(rem / g.arc) * (.pi / 2)
            return cornerPoint(cx: R.minX + r, cy: R.maxY - r, r: r, angle: a)
        }
        rem -= g.arc

        // 7. left edge: (minX, maxY - r) → (minX, minY + r); outward left
        if rem <= g.side {
            return (CGPoint(x: R.minX, y: R.maxY - r - rem), .pi)
        }
        rem -= g.side

        // 8. top-left corner: center (minX + r, minY + r), 180° → 270°
        if rem <= g.arc {
            let a = Double.pi + Double(rem / g.arc) * (.pi / 2)
            return cornerPoint(cx: R.minX + r, cy: R.minY + r, r: r, angle: a)
        }
        rem -= g.arc

        // 9. top edge, left half: (minX + r, minY) → (midX, minY); outward up
        return (CGPoint(x: R.minX + r + rem, y: R.minY), -.pi / 2)
    }

    private static func cornerPoint(cx: CGFloat, cy: CGFloat, r: CGFloat, angle: Double) -> (point: CGPoint, normal: Double) {
        let p = CGPoint(x: cx + r * CGFloat(cos(angle)), y: cy + r * CGFloat(sin(angle)))
        return (p, angle)   // outward normal == radial angle from the corner center
    }
}
