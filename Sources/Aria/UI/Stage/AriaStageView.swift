import SwiftUI

/// Renders Aria's on-screen presence beyond her HUD: guidance markers she pools
/// onto things to point them out, and the worker blobs she spawns while running
/// agentic work. Drawn in a passive, click-through overlay (`AriaStageController`).
/// One gated `TimelineView` is the clock; nothing renders when the stage is empty.
struct AriaStageView: View {
    @ObservedObject var stage: AriaStage
    var accent: Color
    var screenSize: CGSize

    var body: some View {
        ZStack {
            if stage.isActive {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(stage.markers) { m in marker(m, t: t) }
                        workerSwarm(t: t)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: Guidance marker

    private func color(_ hex: String) -> Color { Theme.color(fromHex: hex) ?? accent }

    private func marker(_ m: AriaStage.Marker, t: Double) -> some View {
        let c = color(m.colorHex)
        let pulse = 0.5 + 0.5 * sin(t * 2.4)
        let radii = BlobMath.radii(t: t * 1.1, n: 11, amp: 0.26, speed: 1.0)
        return ZStack {
            // Expanding ping ring.
            Circle()
                .stroke(c.opacity(0.55 * (1 - pulse)), lineWidth: 3)
                .frame(width: 44 + 38 * pulse, height: 44 + 38 * pulse)
            // The pooled blob itself.
            BlobShape(radii: radii)
                .fill(RadialGradient(colors: [c.opacity(0.95), c.opacity(0.45)],
                                     center: .center, startRadius: 1, endRadius: 28))
                .frame(width: 40, height: 40)
                .shadow(color: c.opacity(0.7), radius: 12)
            if let label = m.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(c.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .fixedSize()
                    .offset(y: -44)
            }
        }
        .position(clampToScreen(m.point))
    }

    // MARK: Worker swarm

    @ViewBuilder
    private func workerSwarm(t: Double) -> some View {
        if !stage.workers.isEmpty {
            let anchor = clampToScreen(stage.workerAnchor ?? CGPoint(x: screenSize.width - 120, y: screenSize.height - 140))
            let n = stage.workers.count
            ForEach(Array(stage.workers.enumerated()), id: \.element.id) { idx, w in
                let fi = Double(idx)
                let angle = fi / Double(n) * 2 * .pi + t * 1.1
                let r = 46.0 + 10.0 * sin(t * 1.6 + fi)
                let pt = CGPoint(x: anchor.x + cos(angle) * r, y: anchor.y + sin(angle) * r)
                let radii = BlobMath.radii(t: t * 1.3 + fi * 0.8, n: 10, amp: 0.34, speed: 1.2)
                BlobShape(radii: radii)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .shadow(color: accent.opacity(0.6), radius: 6)
                    .position(pt)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 30), max(screenSize.width - 30, 30)),
                y: min(max(p.y, 30), max(screenSize.height - 30, 30)))
    }
}
