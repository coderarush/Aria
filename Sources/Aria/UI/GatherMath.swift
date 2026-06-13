import CoreGraphics
import Foundation

/// Pure motion for the "gather" animation: when Aria consolidates, light streams
/// in from points all around the screen edge and coalesces into the blob. Each
/// streamer flies from its perimeter start to the blob center on an eased path,
/// with a slight organic stagger and a glow envelope that fades as it merges.
/// Kept pure so the convergence can be unit-tested without rendering.
enum GatherMath {

    /// Streamer `i` of `n` at consolidate progress `p ∈ [0,1]`.
    /// - `pos`: current head position (start → center as p rises).
    /// - `glow`: 0…1 brightness envelope (0 at birth and at the moment it merges).
    /// - `start`: its fixed perimeter origin (useful for drawing a motion tail).
    static func streamer(i: Int, n: Int, progress p: Double,
                         rect: CGRect, cornerRadius: CGFloat, center: CGPoint)
        -> (pos: CGPoint, glow: Double, start: CGPoint) {
        let startU = (Double(i) + 0.5) / Double(max(n, 1))
        let start = BorderMath.point(u: startU, in: rect, cornerRadius: cornerRadius).point

        // Golden-ratio scatter → streamers leave at slightly different times.
        let frac = (Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let delay = 0.22 * frac
        let pe = smoothstep(delay, 1.0, p)
        let eased = easeInOutCubic(pe)

        let pos = CGPoint(x: start.x + (center.x - start.x) * CGFloat(eased),
                          y: start.y + (center.y - start.y) * CGFloat(eased))
        let rise = smoothstep(0.0, 0.18, pe)
        let fall = 1.0 - smoothstep(0.82, 1.0, pe)
        return (pos, rise * fall, start)
    }

    static func easeInOutCubic(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x < a ? 0 : 1 }
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
