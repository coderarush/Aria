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
    // 2a: Typewriter caption reveal
    @State private var displayedCaption = ""
    @State private var captionTask: Task<Void, Never>? = nil
    @State private var cursorVisible = false
    @State private var cursorTimer: Timer?
    // 2b: Blob entrance burst particles
    @State private var showBurstParticles = false
    // 2f: State transition color flash
    @State private var flashIntensity: Double = 0
    // Thinking: the body splits into a ring of small blobs that orbit, then
    // squish back together when she's done. 0 = whole blob, 1 = fully split.
    @State private var thinkingSplit: Double = 0

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
        if viewModel.isDictating && viewModel.state == .listening { return "Dictating…" }
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
        .onChange(of: viewModel.state) { _, newState in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
            // 2f: Flash the blob white briefly on every state transition.
            flashIntensity = 0.4
            withAnimation(.easeOut(duration: 0.35)) { flashIntensity = 0 }
            // Split into orbiting blobs while thinking; merge back otherwise. A
            // springy response with a touch of overshoot gives the "pull apart /
            // snap together" feel. Opt-out via Settings → calmer shimmer only.
            withAnimation(.spring(response: 0.62, dampingFraction: 0.66)) {
                thinkingSplit = (newState == .thinking && settings.expressiveThinking) ? 1 : 0
            }
        }
        .onChange(of: choreographer.kind) { _, kind in
            // The blob is only draggable when fully settled; the instant she
            // leaves that phase (splash, consolidate-out, dismiss) the panel
            // returns to fully click-through so no stale region swallows clicks.
            if kind != .blob { onBlobFrameChange?(nil) }
            // 2b: Trigger particle burst when the blob first appears.
            if kind == .blob {
                showBurstParticles = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showBurstParticles = false }
            }
        }
        // Typewriter for streamed response text: append only NEW characters so
        // each streaming delta extends the display without restarting from zero.
        .onChange(of: viewModel.responseText) { _, newText in
            let alreadyShown = displayedCaption.count
            guard newText.count > alreadyShown else {
                // Text shrank or cleared (new turn) — reset.
                captionTask?.cancel(); displayedCaption = ""; return
            }
            let newChars = String(newText.dropFirst(alreadyShown))
            captionTask?.cancel()
            captionTask = Task {
                for char in newChars {
                    guard !Task.isCancelled else { break }
                    displayedCaption.append(char)
                    try? await Task.sleep(nanoseconds: 18_000_000)
                }
            }
        }
        // For non-response state labels ("Thinking…" etc.) clear the typewriter buffer.
        .onChange(of: viewModel.state) { _, state in
            if state != .responding && state != .error {
                captionTask?.cancel()
                displayedCaption = ""
            }
        }
        // Blinking cursor for the typewriter effect — runs ONLY while a
        // response is on screen. A repeats-forever timer here kept the whole
        // HUD invalidating at 2 Hz even when idle (and leaked one timer per
        // onAppear); scoping it to the responding states costs nothing at rest.
        .onChange(of: viewModel.state) { _, state in
            cursorTimer?.invalidate()
            cursorTimer = nil
            if state == .responding || state == .error {
                cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    Task { @MainActor in cursorVisible.toggle() }
                }
            } else {
                cursorVisible = false
            }
        }
        .onDisappear {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }
    }

    // MARK: - Composited presence

    @ViewBuilder
    private func presenceContent(t: Double, size: CGSize) -> some View {
        let borderIntensity = choreographer.borderIntensity(at: t)
        ZStack {
            // The screen-edge glow (listening / executing / transitions). Shares
            // the one clock — `t` — so there's no second TimelineView to drift.
            // Boost intensity by audio level while listening so the border pulses
            // with the user's voice — the audio-reactive effect lives here, not
            // as a separate ring around the blob.
            let audioBoost = viewModel.state == .listening
                ? Double(viewModel.audioLevel) * 0.55
                : 0
            if borderIntensity + audioBoost > 0.001 {
                ScreenBorderView(t: t, palette: palette,
                                 intensity: min(borderIntensity + audioBoost, 1.0),
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
        // 2d: More dramatic audio reactivity for listening.
        let amp = 0.07 + level * 0.28 + speaking * 0.15 + (thinking ? 0.09 : 0)
                + breathe * 0.04 + choreographer.blobAmpBoost(at: t)
        // Slower morph = silkier, liquid-glass squirm.
        let speed = thinking ? 1.3 : 0.75
        // 2d: Stronger envelope scale for listening.
        let envScale = 1 + level * 0.20 + speaking * 0.18 + breathe * 0.06
        let radii = BlobMath.radii(t: t, n: 11, amp: amp, speed: speed)
        let c0 = palette.first ?? viewModel.accent
        let c1 = palette.count > 1 ? palette[1] : c0
        // Pre-folded so the modifier chain stays cheap to type-check.
        let fall = choreographer.blobFall(at: t)
        let squash = fall > 0.8 ? 1 - (fall - 0.8) / 0.2 * 0.18 : 1
        let dragScale = isDragging ? 1.05 : 1.0
        // 2e: Bigger pulse scale.
        let pulseScale = pulse ? 1.10 : 1.0
        let combinedScale = dragScale * choreographer.blobScale(at: t) * pulseScale * settings.orbScale
        // Liquid-glass: the specular highlight drifts slowly so light slides over
        // her like a glass bead, and a faint top sheen reads as a refractive edge.
        let gx = 0.38 + 0.05 * sin(t * 0.5)
        let gy = 0.30 + 0.04 * cos(t * 0.42)

        return ZStack {
            BlobShape(radii: radii)
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
                // 2f: State transition flash overlay.
                .overlay(
                    BlobShape(radii: radii)
                        .fill(Color.white.opacity(flashIntensity))
                        .blendMode(.plusLighter)
                )
                .frame(width: 150, height: 150)
                .scaleEffect(x: envScale, y: envScale * squash)
                .scaleEffect(combinedScale * (1 - 0.30 * thinkingSplit))
                // As she splits, the whole body dissolves into the orbiting blobs.
                .opacity(1 - thinkingSplit)
                .shadow(color: .black.opacity(0.22 * (1 - thinkingSplit)), radius: 10, y: 7)
                .shadow(color: c0.opacity((0.28 + (suggesting ? 0.25 * breathe : 0)) * (1 - thinkingSplit)),
                        radius: 16 + (suggesting ? 10 * breathe : 0))

            // The thinking constellation: the body pulled apart into a ring of
            // small morphing blobs that orbit (and gently bob against) each other.
            thinkingConstellation(t: t, split: thinkingSplit, combinedScale: combinedScale)

            // 2c: Rotating shimmer ring while thinking. With the split animation on
            // it fades in with the split; with it off it's the sole thinking cue.
            if thinking {
                Circle()
                    .stroke(
                        AngularGradient(colors: [.clear, (palette.first ?? .purple).opacity(0.6), .clear],
                                       center: .center),
                        lineWidth: 2
                    )
                    .frame(width: 176, height: 176)
                    .rotationEffect(.degrees(t * 120))
                    .opacity(settings.expressiveThinking ? 0.6 * thinkingSplit : 0.65)
                    .blendMode(.plusLighter)
            }

            // 2b: Burst particles on blob entrance.
            if showBurstParticles {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6.0 * .pi * 2
                    let dx = showBurstParticles ? cos(angle) * 40 : 0
                    let dy = showBurstParticles ? sin(angle) * 40 : 0
                    Circle()
                        .fill(palette.first ?? .purple)
                        .frame(width: 6, height: 6)
                        .opacity(showBurstParticles ? 0 : 0.7)
                        .offset(x: dx, y: dy)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.02), value: showBurstParticles)
                }
            }
        }
        .frame(width: 184, height: 184)
        // 2e: Snappier spring physics.
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: pulse)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isDragging)
    }

    /// The orbiting small blobs she becomes while thinking. Each starts at the
    /// center (split 0, scale 0) and spirals out to its place on a slowly rotating
    /// ring (split 1), morphing and bobbing so the cluster looks alive — then
    /// reverses back into the body when thinking ends. Pure function of `t`+`split`.
    @ViewBuilder
    private func thinkingConstellation(t: Double, split: Double, combinedScale: Double) -> some View {
        if split > 0.001 {
            let n = 6
            let c0 = palette.first ?? viewModel.accent
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    let fi = Double(i)
                    // Ring rotation + per-blob bob makes them weave around each other.
                    let angle = fi / Double(n) * 2 * .pi + t * 0.85
                    let ringR = (50.0 + 9.0 * sin(t * 1.4 + fi * 1.7)) * split
                    // A short spiral as they emerge: more spin when less split.
                    let dx = cos(angle) * ringR
                    let dy = sin(angle) * ringR
                    let radii = BlobMath.radii(t: t * 1.25 + fi * 0.9, n: 10, amp: 0.32, speed: 1.15)
                    let sz = (16.0 + 26.0 * split) * combinedScale
                    let col = palette.count > 1 ? palette[i % palette.count] : c0
                    BlobShape(radii: radii)
                        .fill(LinearGradient(colors: [col, col.opacity(0.62)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            BlobShape(radii: radii)
                                .fill(RadialGradient(colors: [.white.opacity(0.5), .clear],
                                                     center: .init(x: 0.36, y: 0.30), startRadius: 1, endRadius: sz * 0.5))
                        )
                        .frame(width: sz, height: sz)
                        .shadow(color: col.opacity(0.55), radius: 7)
                        .offset(x: dx, y: dy)
                        .opacity(min(1, split * 1.3))
                }
            }
            .blur(radius: 2.2 * (1 - split))   // soft "un-resolving" as they split off
        }
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
        // Typewriter effect only on response text — status labels ("Thinking…") appear instantly.
        let isResponse = viewModel.state == .responding || viewModel.state == .error
        let shownText = isResponse
            ? displayedCaption + (cursorVisible ? "|" : " ")
            : captionText
        return Group {
            if showCaption {
                Text(shownText)
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
