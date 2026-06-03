import SwiftUI
import AppKit

/// Aria's Siri-style presence: a living aurora of soft accent light that drifts
/// around the screen edges, drawn with an additive-blended Canvas for a smooth,
/// high-end glow. The center is transparent and click-through. A bottom caption
/// shows her reply.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

    private var captionText: String {
        switch viewModel.state {
        case .listening: return "Listening…"
        case .thinking:  return "Thinking…"
        case .responding, .error: return viewModel.responseText
        case .idle:      return ""
        }
    }
    private var showCaption: Bool { active && !captionText.isEmpty }

    var body: some View {
        ZStack {
            Color.clear
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    draw(ctx, size, t: timeline.date.timeIntervalSinceReferenceDate)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .opacity(active ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: active)
        }
        .overlay(alignment: .bottom) { caption }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Aurora

    private struct RGBA { var r = 0.0, g = 0.0, b = 0.0
        init(_ c: Color) { let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
            r = n.redComponent; g = n.greenComponent; b = n.blueComponent } }

    /// Smoothly interpolate a palette (wrapping) at fraction f∈[0,1).
    private func blended(_ c: [RGBA], _ f: Double) -> Color {
        guard c.count > 1 else { let x = c.first ?? RGBA(.white)
            return Color(.sRGB, red: x.r, green: x.g, blue: x.b, opacity: 1) }
        let scaled = (f - floor(f)) * Double(c.count)
        let i0 = Int(floor(scaled)) % c.count
        let i1 = (i0 + 1) % c.count
        let t = scaled - floor(scaled)
        let a = c[i0], b = c[i1]
        return Color(.sRGB, red: a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, opacity: 1)
    }

    /// Many overlapping, low-opacity, smoothly color-shifting blobs ride around the
    /// perimeter; additive blending merges them into a continuous aurora.
    private func draw(_ context: GraphicsContext, _ size: CGSize, t: Double) {
        var ctx = context
        ctx.blendMode = .plusLighter
        ctx.opacity = breathing(t)

        let palette = viewModel.glowColors.isEmpty ? [viewModel.accent] : viewModel.glowColors
        let comps = palette.map(RGBA.init)
        let blobs = 16
        let level = viewModel.state == .listening ? CGFloat(min(max(viewModel.audioLevel, 0), 1)) : 0
        let baseR = min(size.width, size.height) * (0.20 + level * 0.07)
        let driftSpeed = viewModel.state == .thinking ? 0.05 : 0.028

        for i in 0..<blobs {
            let f = Double(i) / Double(blobs)
            let p = perimeterPoint(t * driftSpeed + f, size)
            let col = blended(comps, f + t * 0.02)            // color flows around + over time
            let wobble = (sin(t * 0.5 + Double(i) * 1.1) + 1) / 2
            let r = baseR * (0.85 + 0.3 * CGFloat(wobble))
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let grad = Gradient(stops: [
                .init(color: col.opacity(0.30 + 0.18 * Double(level)), location: 0.0),
                .init(color: col.opacity(0.09), location: 0.5),
                .init(color: col.opacity(0.0), location: 1.0),
            ])
            ctx.fill(Path(ellipseIn: rect),
                     with: .radialGradient(grad, center: p, startRadius: 0, endRadius: r))
        }
    }

    /// Gentle global breathing of the whole aurora.
    private func breathing(_ t: Double) -> Double {
        0.82 + 0.18 * (sin(t * 1.1) + 1) / 2
    }

    /// Map u (any real; fractional part used) to a point traveling clockwise
    /// around the screen rectangle's perimeter. Blob centers sit on the edge so
    /// only their inner half shows — the glow hugs the border.
    private func perimeterPoint(_ u: Double, _ size: CGSize) -> CGPoint {
        let w = size.width, h = size.height
        let peri = 2 * (w + h)
        var d = u.truncatingRemainder(dividingBy: 1)
        if d < 0 { d += 1 }
        d *= peri
        if d < w { return CGPoint(x: d, y: 0) }            // top, L→R
        d -= w
        if d < h { return CGPoint(x: w, y: d) }            // right, T→B
        d -= h
        if d < w { return CGPoint(x: w - d, y: h) }        // bottom, R→L
        d -= w
        return CGPoint(x: 0, y: h - d)                     // left, B→T
    }

    // MARK: Caption

    private var caption: some View {
        Group {
            if showCaption {
                Text(captionText)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24).padding(.vertical, 15)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(viewModel.accent.opacity(0.4), lineWidth: 1))
                    .shadow(color: viewModel.accent.opacity(0.3), radius: 24, y: 8)
                    .frame(maxWidth: 720)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showCaption)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.responseText)
    }
}
