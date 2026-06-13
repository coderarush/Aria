import SwiftUI

/// Aria living on the screen's edge: a faint, organic perimeter glow in the same
/// brand language as the blob (gradient palette, gooey, alive), with a brighter
/// "comet" of light drifting slowly around the rim. This is what she becomes
/// while listening and while executing a multi-step task.
///
/// All geometry comes from `BorderMath`; this view only paints. It is purely
/// decorative and click-through — it never intercepts mouse events.
struct ScreenBorderView: View {
    /// Blob palette (first two colors used for the gradient sweep).
    var palette: [Color]
    /// Master opacity 0…1 — the choreographer drains this during consolidate and
    /// raises it during wake/ignite.
    var intensity: Double
    /// Splash-ignition gate. `nil` = full ring lit. Otherwise only the arc within
    /// `phase·0.5` of bottom-center (u = 0.5) is lit, spreading both ways as it
    /// rises 0 → 1.
    var sweepPhase: Double?

    private let inset: CGFloat = 7
    private let cornerRadius: CGFloat = 26
    private let samples = 200

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // ~12s per lap — calm, ambient, never busy.
            let head = (t * 0.083).truncatingRemainder(dividingBy: 1)
            Canvas { ctx, size in
                guard intensity > 0.001 else { return }
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                let c0 = palette.first ?? .accentColor
                let c1 = palette.count > 1 ? palette[1] : c0
                let tail = 0.18

                for i in 0..<samples {
                    let u = Double(i) / Double(samples)
                    if let phase = sweepPhase, abs(u - 0.5) > max(0, phase) * 0.5 { continue }

                    let (p, _) = BorderMath.point(u: u, in: rect, cornerRadius: cornerRadius)
                    // Organic width/brightness wobble so the rim breathes like the blob.
                    let wob = 0.5 + 0.5 * sin(t * 1.3 + u * 18)
                    let comet = BorderMath.cometIntensity(u: u, head: head, tail: tail)

                    let base = 0.16 + 0.06 * wob           // faint ambient ring
                    let alpha = (base + comet * 0.7) * intensity
                    let r = (3.0 + 2.2 * wob + comet * 7.0) // comet swells the dot

                    let col = blend(c0, c1, u)
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(col.opacity(min(1, alpha))))
                }
            }
            // Soft bloom so the dots read as a continuous gel rim, not beads.
            .blur(radius: 5)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// Linear color blend; SwiftUI has no built-in, so interpolate components.
    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        #if canImport(AppKit)
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        let f = CGFloat(t)
        return Color(red: Double(na.redComponent + (nb.redComponent - na.redComponent) * f),
                     green: Double(na.greenComponent + (nb.greenComponent - na.greenComponent) * f),
                     blue: Double(na.blueComponent + (nb.blueComponent - na.blueComponent) * f))
        #else
        return t < 0.5 ? a : b
        #endif
    }
}
