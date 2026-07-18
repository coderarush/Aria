import SwiftUI

/// The Lens canvas: a full-screen, see-through surface where the user circles or
/// scribbles on whatever app is beneath. The ink is rendered in Aria's gooey
/// idiom — a glowing accent stroke trailed by a handful of small morphing blobs
/// (the same `BlobShape` as her presence), so "circle to explain" feels like
/// Aria reaching onto your screen rather than a generic marquee. One gated
/// `TimelineView` is the only clock.
struct LensCanvasView: View {
    @ObservedObject var session: LensSession
    /// Fired on release in explain mode with the completed stroke.
    var onComplete: ([CGPoint]) -> Void
    /// Fired on a bare tap (no real stroke) in explain mode — treated as cancel.
    var onCancel: () -> Void

    private var allStrokes: [[CGPoint]] { session.strokes + (session.current.isEmpty ? [] : [session.current]) }

    var body: some View {
        ZStack {
            // Faint scrim: signals "you're in Lens" without hiding what's beneath.
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ForEach(Array(allStrokes.enumerated()), id: \.offset) { _, stroke in
                strokeInk(stroke)
            }

            hint
        }
        .contentShape(Rectangle())
        .gesture(drawGesture)
    }

    // MARK: Ink

    private var inkGradient: LinearGradient {
        let cols = session.palette.count >= 2 ? session.palette : [session.accent, session.accent.opacity(0.6)]
        return LinearGradient(colors: cols, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private func strokeInk(_ stroke: [CGPoint]) -> some View {
        if stroke.count > 1 {
            LensInkShape(points: stroke)
                .stroke(inkGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .shadow(color: session.accent.opacity(0.55), radius: 14)
                .shadow(color: session.accent.opacity(0.30), radius: 28)
                .allowsHitTesting(false)
        }
    }

    // MARK: Hint

    private var hint: some View {
        VStack {
            Text(session.mode == .explain ? "Circle anything — Aria will explain it"
                                          : "Draw on your screen · Esc to finish")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(session.accent.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(.top, 56)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: Gesture

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in session.current.append(v.location) }
            .onEnded { _ in
                let stroke = session.current
                session.current = []
                switch session.mode {
                case .explain:
                    if stroke.count >= 3 { onComplete(stroke) } else { onCancel() }
                case .draw:
                    if stroke.count > 1 { session.strokes.append(stroke) }
                }
            }
    }
}

/// Catmull-Rom smoothing of a freehand polyline → a gooey, cornerless ink path
/// (same curve family as `BlobShape`, so Lens ink matches Aria's blob).
struct LensInkShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        guard points.count > 2 else {
            path.move(to: points[0]); path.addLine(to: points[1]); return path
        }
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
