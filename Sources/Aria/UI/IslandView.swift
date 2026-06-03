import SwiftUI

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

    /// Soft accent blobs ride around the screen perimeter; additive blending
    /// layers them into a glowing aurora that hugs the edges and bleeds inward.
    private func draw(_ context: GraphicsContext, _ size: CGSize, t: Double) {
        var ctx = context
        ctx.blendMode = .plusLighter
        ctx.opacity = breathing(t)

        let accent = viewModel.accent
        let blobs = 9
        // Listening makes the aurora swell and brighten with the voice.
        let level = viewModel.state == .listening ? CGFloat(min(max(viewModel.audioLevel, 0), 1)) : 0
        let thinking = viewModel.state == .thinking
        let baseRadius = min(size.width, size.height) * (0.17 + level * 0.07)
        let driftSpeed = thinking ? 0.045 : 0.026

        for i in 0..<blobs {
            let phase = Double(i) / Double(blobs)
            let u = t * driftSpeed + phase
            let p = perimeterPoint(u, size)
            // Each blob wobbles in size for a living, non-mechanical feel.
            let wobble = (sin(t * 0.6 + Double(i) * 1.3) + 1) / 2          // 0…1
            let r = baseRadius * (0.75 + 0.45 * CGFloat(wobble))
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)

            let hot = accent.opacity(0.55 + 0.25 * Double(level))
            let grad = Gradient(stops: [
                .init(color: hot, location: 0.0),
                .init(color: accent.opacity(0.18), location: 0.45),
                .init(color: accent.opacity(0.0), location: 1.0),
            ])
            ctx.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(grad, center: p, startRadius: 0, endRadius: r))
        }

        // A faint white core sheen on top adds a glassy, premium edge.
        ctx.blendMode = .plusLighter
        for i in 0..<blobs {
            let phase = Double(i) / Double(blobs) + 0.5 / Double(blobs)
            let u = t * driftSpeed + phase
            let p = perimeterPoint(u, size)
            let r = baseRadius * 0.5
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let grad = Gradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)])
            ctx.fill(
                Path(ellipseIn: rect),
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
