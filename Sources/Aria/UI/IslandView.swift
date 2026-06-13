import SwiftUI

/// Aria's presence. She is three things that flow into one another: a faint glow
/// rotating around the screen edge (listening / executing), an organic morphing
/// blob that pools at your chosen corner (thinking / answering), and nothing at
/// all when idle. The `PresenceChoreographer` runs the water-like transitions
/// between them; a single gated TimelineView is the only clock, so an idle Aria
/// does zero rendering work.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @StateObject private var choreographer = PresenceChoreographer()
    @ObservedObject private var settings = AppSettings.shared
    @State private var pulse = false           // springy pop on state change
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    /// Reported up to the hosting panel so it can make ONLY the blob interactive.
    var onBlobFrameChange: ((CGRect?) -> Void)?

    private var presenceMode: PresenceMode {
        PresenceMode.from(state: viewModel.state,
                          visible: viewModel.isVisible,
                          hasSuggestion: viewModel.hasSuggestion)
    }

    /// The TimelineView (and all work) exists only while something is on screen.
    private var isActive: Bool {
        presenceMode != .hidden || choreographer.kind != .hidden
    }

    private var palette: [Color] {
        let c = viewModel.glowColors.isEmpty ? [viewModel.accent, viewModel.accent] : viewModel.glowColors
        return c
    }

    /// A synthetic speech envelope (~0…1) so the blob breathes while she talks.
    static func speechEnv(_ t: Double) -> Double {
        // Slower, detuned cadence → a smooth, silky "she's talking" pull (not jitter).
        let e = 0.55 + 0.45 * (0.55 * sin(t * 5.2) + 0.30 * sin(t * 8.1) + 0.15 * sin(t * 3.3))
        return max(0, min(1, e))
    }

    private var captionText: String {
        switch viewModel.state {
        case .listening: return "Listening…"
        case .thinking:  return "Thinking…"
        case .executing: return "Working…"
        case .responding, .error: return viewModel.responseText
        case .idle:      return ""
        }
    }
    private var showCaption: Bool {
        viewModel.isVisible && viewModel.state != .idle && !captionText.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                if isActive {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        presenceContent(t: t, size: geo.size)
                            .onChange(of: t) { _, now in
                                // Single clock: keep the choreographer's target in
                                // sync with the live mode, then advance the phase.
                                choreographer.setMode(presenceMode, now: now)
                                choreographer.advance(now: now)
                            }
                    }
                }
            }
            .overlay(alignment: .bottom) { caption }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.state) { _, _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
        }
        .onChange(of: choreographer.kind) { _, kind in
            // The blob is only draggable when fully settled; the instant she
            // leaves that phase (splash, consolidate-out, dismiss) the panel
            // returns to fully click-through so no stale region swallows clicks.
            if kind != .blob { onBlobFrameChange?(nil) }
        }
    }

    // MARK: - Composited presence

    @ViewBuilder
    private func presenceContent(t: Double, size: CGSize) -> some View {
        let borderIntensity = choreographer.borderIntensity(at: t)
        ZStack {
            // The screen-edge glow (listening / executing / transitions). Shares
            // the one clock — `t` — so there's no second TimelineView to drift.
            if borderIntensity > 0.001 {
                ScreenBorderView(t: t, palette: palette,
                                 intensity: borderIntensity,
                                 sweepPhase: choreographer.borderSweep(at: t))
            }
            // The gather: light streaming from the edge into the blob as she pools.
            if let cp = choreographer.consolidateProgress(at: t) {
                EdgeGatherView(palette: palette, progress: cp, center: restingCenter(in: size))
            }
            // The blob (thinking / answering / suggestion / pooling / splashing).
            if choreographer.showsBlob {
                blobBody(t: t)
                    .background(blobFrameReporter(size: size))
                    .position(blobPosition(in: size, t: t))
                    .allowsHitTesting(choreographer.kind == .blob)
                    .gesture(blobDrag(in: size))
            }
        }
    }

    /// The morphing blob, fed `t` from the shared clock (no nested TimelineView).
    private func blobBody(t: Double) -> some View {
        let level = viewModel.state == .listening ? Double(min(max(viewModel.audioLevel, 0), 1)) : 0
        let speaking = viewModel.state == .responding ? Self.speechEnv(t) : 0
        let thinking = viewModel.state == .thinking
        let suggesting = viewModel.hasSuggestion && viewModel.state == .idle
        let breathe = suggesting ? (0.5 + 0.5 * sin(t * 1.8)) : 0
        let amp = 0.07 + level * 0.16 + speaking * 0.13 + (thinking ? 0.07 : 0)
                + breathe * 0.04 + choreographer.blobAmpBoost(at: t)
        // Slower morph = silkier, liquid-glass squirm.
        let speed = thinking ? 1.3 : 0.75
        // A clearer "pull" while she speaks so you can see she's talking.
        let envScale = 1 + level * 0.12 + speaking * 0.16 + breathe * 0.06
        let radii = BlobMath.radii(t: t, n: 11, amp: amp, speed: speed)
        let c0 = palette.first ?? viewModel.accent
        let c1 = palette.count > 1 ? palette[1] : c0
        // Pre-folded so the modifier chain stays cheap to type-check.
        let fall = choreographer.blobFall(at: t)
        let squash = fall > 0.8 ? 1 - (fall - 0.8) / 0.2 * 0.18 : 1
        let dragScale = isDragging ? 1.05 : 1.0
        let pulseScale = pulse ? 1.06 : 1.0
        let combinedScale = dragScale * choreographer.blobScale(at: t) * pulseScale * settings.orbScale
        // Liquid-glass: the specular highlight drifts slowly so light slides over
        // her like a glass bead, and a faint top sheen reads as a refractive edge.
        let gx = 0.38 + 0.05 * sin(t * 0.5)
        let gy = 0.30 + 0.04 * cos(t * 0.42)

        return BlobShape(radii: radii)
            .fill(LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                BlobShape(radii: radii)
                    .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                         center: .init(x: gx, y: gy), startRadius: 1, endRadius: 62))
            )
            .overlay(
                BlobShape(radii: radii)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                         startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
            )
            .frame(width: 150, height: 150)
            .scaleEffect(x: envScale, y: envScale * squash)
            .scaleEffect(combinedScale)
            .shadow(color: .black.opacity(0.22), radius: 10, y: 7)
            .shadow(color: c0.opacity(0.28 + (suggesting ? 0.25 * breathe : 0)),
                    radius: 16 + (suggesting ? 10 * breathe : 0))
            .frame(width: 184, height: 184)
            .animation(.spring(response: 0.5, dampingFraction: 0.72), value: pulse)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: isDragging)
    }

    // MARK: - Positioning

    /// Resting screen-space center of the blob (anchor if dragged, else the
    /// legacy `orbPosition` corner). Caption stays bottom-anchored regardless.
    private func restingCenter(in size: CGSize) -> CGPoint {
        if let a = settings.orbAnchor {
            return CGPoint(x: a.x * size.width, y: a.y * size.height)
        }
        let bottomY = size.height - 120
        switch settings.orbPosition {
        case .bottomRight: return CGPoint(x: size.width - 120, y: bottomY)
        default:           return CGPoint(x: size.width / 2, y: bottomY)
        }
    }

    /// Live blob center: resting point, plus the splash fall, plus any drag.
    private func blobPosition(in size: CGSize, t: Double) -> CGPoint {
        let base = restingCenter(in: size)
        let fall = choreographer.blobFall(at: t)
        let eased = fall * fall                       // ease-in
        let bottomY = size.height - 40
        let y = base.y + (bottomY - base.y) * eased
        return CGPoint(x: base.x + dragOffset.width, y: y + dragOffset.height)
    }

    private func blobFrameReporter(size: CGSize) -> some View {
        GeometryReader { g -> Color in
            let f = g.frame(in: .global)
            DispatchQueue.main.async {
                if choreographer.kind == .blob { onBlobFrameChange?(f) }
            }
            return Color.clear
        }
    }

    private func blobDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard choreographer.kind == .blob else { return }
                isDragging = true
                dragOffset = v.translation
            }
            .onEnded { v in
                guard isDragging else { return }
                isDragging = false
                let base = restingCenter(in: size)
                let cx = base.x + v.translation.width
                let cy = base.y + v.translation.height
                let nx = min(max(cx / size.width, 0.06), 0.94)
                let ny = min(max(cy / size.height, 0.06), 0.94)
                settings.orbAnchor = CGPoint(x: nx, y: ny)
                dragOffset = .zero
            }
    }

    // MARK: - Caption

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
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: showCaption)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.responseText)
    }
}
