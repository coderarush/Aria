import SwiftUI

/// The "gather" animation: during consolidation, light streams in from all around
/// the screen edge and coalesces into the blob. Each streamer is a soft glowing
/// head with a short motion tail trailing back toward its origin on the rim, so
/// the whole perimeter visibly collapses inward into the droplet.
///
/// Geometry comes from `GatherMath`; this view only paints, and is purely
/// decorative + click-through.
struct EdgeGatherView: View {
    var palette: [Color]
    /// Consolidate progress 0…1 (from the choreographer's `consolidating` phase).
    var progress: Double
    /// Blob target in this view's coordinate space.
    var center: CGPoint

    private let inset: CGFloat = 6
    private let cornerRadius: CGFloat = 28
    private let count = 30

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let colors = palette.isEmpty ? [Color.accentColor] : palette
            for i in 0..<count {
                let s = GatherMath.streamer(i: i, n: count, progress: progress,
                                            rect: rect, cornerRadius: cornerRadius, center: center)
                guard s.glow > 0.02 else { continue }
                let hue = colors[i % colors.count]

                // Motion tail: where this streamer was a moment ago.
                let prev = GatherMath.streamer(i: i, n: count, progress: max(0, progress - 0.06),
                                               rect: rect, cornerRadius: cornerRadius, center: center).pos

                // Draw the tail as a few fading dots from prev → pos (cheap streak).
                let steps = 4
                for k in 0...steps {
                    let f = CGFloat(k) / CGFloat(steps)
                    let x = prev.x + (s.pos.x - prev.x) * f
                    let y = prev.y + (s.pos.y - prev.y) * f
                    let r = (2.0 + 7.0 * Double(f)) * s.glow          // tail thin → head fat
                    let a = s.glow * (0.18 + 0.55 * Double(f))
                    let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(hue.opacity(min(1, a))))
                }
            }
        }
        .blur(radius: 6)
        .compositingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
