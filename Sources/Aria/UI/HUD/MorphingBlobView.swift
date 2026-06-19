import SwiftUI

/// The math behind the morphing blob: a set of per-vertex radius multipliers that wobble
/// over time with layered sine noise. Pure + deterministic so it can be unit-tested and
/// tuned without rendering. `amp` is the wobble amount (0 = perfect circle → "top-left"
/// calm; larger = "bottom-middle" amoeba), `speed` scales how fast it squirms.
enum BlobMath {
    static func radii(t: Double, n: Int, amp: Double, speed: Double) -> [CGFloat] {
        guard n >= 3 else { return Array(repeating: 1, count: max(n, 0)) }
        return (0..<n).map { i in
            let a = Double(i)
            // Three detuned waves → an organic, non-repeating outline.
            let w = 0.60 * sin(t * speed + a * 0.9)
                  + 0.30 * sin(t * speed * 1.7 + a * 1.7)
                  + 0.10 * sin(t * speed * 0.5 + a * 2.3)
            return CGFloat(1 + amp * w)
        }
    }
}

/// A smooth closed blob whose outline passes through `radii.count` vertices placed around
/// a circle, each pushed in/out by its radius multiplier. Catmull-Rom interpolation keeps
/// the curve gooey and continuous (no corners). Recreated each TimelineView tick, so the
/// motion comes from feeding new `radii` rather than SwiftUI animation.
struct BlobShape: Shape {
    var radii: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = radii.count
        guard n >= 3 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Leave headroom so the wobble + shadow don't clip.
        let base = min(rect.width, rect.height) / 2 * 0.74

        func point(_ i: Int) -> CGPoint {
            let idx = ((i % n) + n) % n
            let ang = 2 * Double.pi * Double(idx) / Double(n) - Double.pi / 2
            let r = base * radii[idx]
            return CGPoint(x: center.x + CGFloat(cos(ang)) * r,
                           y: center.y + CGFloat(sin(ang)) * r)
        }

        path.move(to: point(0))
        for i in 0..<n {
            let p0 = point(i - 1), p1 = point(i), p2 = point(i + 1), p3 = point(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
