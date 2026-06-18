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
    // 2b: Blob entrance burst particles
    @State private var showBurstParticles = false
    // 2f: State transition color flash
    @State private var flashIntensity: Double = 0
    // Thinking split driven by real time, not SwiftUI animation.
    // thinkingStartT: TimelineView `t` when thinking began (-1 = never)
    // thinkingEndT:   TimelineView `t` when thinking ended (-1 = still thinking)
    @State private var thinkingStartT: Double = -1
    @State private var thinkingEndT:   Double = -1

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

    /// Damped-spring position: x(elapsed) targeting `target`, starting from 0.
    /// response ≈ period in seconds; damping < 1 = underdamped (overshoots).
    /// With response=1.4, damping=0.38 the peak overshoot is ~25 % at t≈0.75 s.
    static func spring(_ elapsed: Double, target: Double = 1.0,
                       response: Double = 1.4, damping: Double = 0.38) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega  = 2 * Double.pi / response
        let zeta   = damping
        let omegaD = omega * sqrt(max(1e-9, 1 - zeta * zeta))
        let decay  = exp(-zeta * omega * elapsed)
        return target * (1 - decay * (cos(omegaD * elapsed)
                                      + (zeta * omega / omegaD) * sin(omegaD * elapsed)))
    }

    /// Compute thinkingSplit value [0…1+overshoot] from the shared clock.
    /// Splitting:  spring 0→1 from thinkingStartT.
    /// Rejoining:  spring 0→1 from thinkingEndT, then ts = 1 − that value.
    func splitTS(at t: Double) -> Double {
        guard thinkingStartT >= 0 else { return 0 }
        if thinkingEndT < 0 {
            // Still thinking: spring toward 1.
            return Self.spring(t - thinkingStartT)
        } else {
            // Done thinking: spring from 1 back toward 0.
            let ts = 1.0 - Self.spring(t - thinkingEndT)
            // Once fully rejoined, reset so the orb section stops rendering.
            if t - thinkingEndT > 3.0 && ts < 0.01 {
                DispatchQueue.main.async {
                    self.thinkingStartT = -1
                    self.thinkingEndT   = -1
                }
            }
            return ts
        }
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
        .onChange(of: viewModel.state) { _, state in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
            // 2f: Flash the blob white briefly on every state transition.
            flashIntensity = 0.4
            withAnimation(.easeOut(duration: 0.35)) { flashIntensity = 0 }
            // Orb split driven by real clock (TimelineView `t`), not SwiftUI animation.
            // We record the timestamp of each transition; blobBody computes the
            // spring value from elapsed time so it's guaranteed smooth every frame.
            let wasThinking = thinkingStartT >= 0 && thinkingEndT < 0
            if state == .thinking {
                // Mark thinking start using wall clock (same epoch as TimelineView t).
                thinkingStartT = Date().timeIntervalSinceReferenceDate
                thinkingEndT   = -1
            } else if wasThinking {
                thinkingEndT = Date().timeIntervalSinceReferenceDate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    flashIntensity = 0.6
                    withAnimation(.easeOut(duration: 0.45)) { flashIntensity = 0 }
                    showBurstParticles = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showBurstParticles = false }
                }
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
        .onAppear {
            // Blinking cursor for typewriter effect.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - Composited presence

    @ViewBuilder
    private func presenceContent(t: Double, size: CGSize) -> some View {
        ZStack {
            // The blob — always the primary presence; fades in on blobIn, out on dismiss.
            if choreographer.showsBlob {
                blobBody(t: t)
                    .opacity(choreographer.blobOpacity(at: t))
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

        // ── Split animation ────────────────────────────────────────────────────────────
        // `ts` is computed from the real clock (same `t` as TimelineView), NOT from
        // SwiftUI animation — so it's guaranteed to interpolate smoothly every frame.
        // Splitting overshoot (ts > 1): orbs slingshot past orbit then pull back.
        // Rejoining overshoot (ts < 0): blob SPLATS to > 100 % scale then settles.
        let ts = splitTS(at: t)

        // Blob deform/dissolve timeline.
        // deformT: 0→1 as ts goes 0.18→1.0 (blob holds full until 0.18, then deforms).
        let blobDelay   = 0.18
        let deformT     = max(0.0, min(1.0, (ts - blobDelay) / (1.0 - blobDelay)))
        // Blob doesn't START shrinking until it has already stretched (deformT≥0.30),
        // and it shrinks FAST after that → big overlap window where blob+orbs coexist.
        let blobShrinkT = max(0.0, (deformT - 0.30) / 0.70)        // 0→1 as deformT 0.30→1.0
        // blobSF: 1→0 while splitting. On rejoin overshoot (ts<0) it pops well above 1 → SPLAT.
        let blobSF      = max(0.0, 1.0 - blobShrinkT) + max(0.0, -ts) * 1.2
        // Alpha lingers (sqrt-ish) so the deformed blob stays visible deep into the split.
        let blobAlpha   = max(0.0, 1.0 - blobShrinkT * blobShrinkT)

        // Taffy stretch: peaks mid-deform (deformT≈0.5) — wide + flat right as orbs tear out.
        let squishAmt   = sin(min(1.0, deformT) * .pi) * 0.50      // up to 50 %
        let splitSX     = 1.0 + squishAmt * 0.85                   // horizontal stretch (≤1.43×)
        let splitSY     = 1.0 - squishAmt * 0.75                   // vertical squeeze (≥0.62×)

        // Orbs: present from ts≈0.12, sitting on the blob's surface, then flung outward.
        // orbsT drives orb size + spread. normTs is the clamped [0,1] orbit progress.
        let orbsT       = max(0.0, (ts - 0.12) / 0.88)             // 0→1+ as ts 0.12→1
        let normTs      = min(1.0, orbsT)

        // Detect split vs rejoin so orbits behave differently each direction.
        let rejoining   = thinkingEndT >= 0
        let maxOrbit    = 58.0                                       // tight cluster

        // Split: orbs emerge from blob skin (50 px) and spread to maxOrbit.
        // Rejoin: orbs converge all the way to CENTER (0 px) so blob grows from them.
        //         Spring overshoot (ts < 0) clamps to 0 — blob pops over the converged orbs.
        let orbitR: Double
        if rejoining {
            orbitR = max(0.0, ts) * maxOrbit                        // 58 → 0 px as ts: 1 → 0
        } else {
            let spreadEase = orbsT * orbsT * (3.0 - 2.0 * orbsT)   // smoothstep
            orbitR = 50.0 + max(0.0, spreadEase) * 8.0             // 50 → 58+ px
        }

        // Elongation during rejoin: orbs stretch radially toward center as they fall in.
        // "Sucked into a vortex" look. 0 = round, 1 = elongated toward center.
        let convergeT   = rejoining ? max(0.0, 1.0 - ts * 2.0) : 0.0  // ramps up as ts drops below 0.5
        let tangElong   = max(0.0, (normTs - 0.50) / 0.50)         // 0→1 as normTs 0.50→1.0
        // ─────────────────────────────────────────────────────────────────────────────────

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
                // splitSX/splitSY: horizontal stretch + vertical squeeze at mid-transition.
                // blobSF: 1→0 while splitting; overshoots above 1.0 on rejoin = satisfying pop.
                .scaleEffect(x: envScale * splitSX, y: envScale * squash * splitSY)
                .scaleEffect(combinedScale * blobSF)
                .opacity(blobAlpha)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 7)
                .shadow(color: c0.opacity(0.28 + (suggesting ? 0.25 * breathe : 0)),
                        radius: 16 + (suggesting ? 10 * breathe : 0))

            // Orbs are PULLED OUT of the blob's surface as it tears apart.
            // They appear at the skin (orbitR≈65 px) the instant the split begins, so the
            // eye reads "blob → pulled into orbs", never a teleport from center.
            if ts > 0.04 || rejoining {
                // Nucleus glow: dims while orbs orbit, blazes bright as they converge.
                // On rejoin the glow swells to signal "they're coming back" before blob pops.
                let nucleusOrbit  = min(1.0, orbsT * 2.0)
                let nucleusRejoin = rejoining ? max(0.0, 1.0 - ts) : 0.0  // 0→1 as ts: 1→0
                let nucleusAlpha  = max(nucleusOrbit * 0.5, nucleusRejoin * 0.9)
                let nucleusR      = 28.0 + nucleusRejoin * 18.0            // swells on rejoin
                Circle()
                    .fill(RadialGradient(colors: [c0.opacity(0.70), .clear],
                                         center: .center, startRadius: 0, endRadius: nucleusR))
                    .frame(width: nucleusR * 2 + 12, height: nucleusR * 2 + 12)
                    .opacity(nucleusAlpha)
                    .blur(radius: 8)

                let orbCount = 12
                ForEach(0..<orbCount, id: \.self) { i in
                    let fi          = Double(i)
                    let baseAngle   = 2.0 * .pi * fi / Double(orbCount)

                    // Each orb has a slightly different angular speed — liquid drift.
                    let speedMult   = 1.0 + 0.07 * sin(fi * 1.37)
                    let angle       = baseAngle + t * 2.0 * speedMult

                    // Radial wobble suppressed during rejoin so convergence reads clean.
                    let wobble      = (rejoining ? 0.3 : 1.0) * sin(t * 1.1 + fi * 0.93) * 4.0
                    let r           = max(0.0, orbitR + wobble)
                    let dx          = cos(angle) * r
                    let dy          = sin(angle) * r

                    // Size: during rejoin, shrink proportionally as they converge (not fade).
                    let sizeT       = min(1.0, orbsT / 0.50)
                    let rejoinShrink = rejoining ? max(0.4, ts) : 1.0  // shrink toward 0.4× as they land
                    let sizeVar     = 0.88 + 0.12 * sin(fi * 0.72)
                    let breathPulse = 0.90 + 0.10 * sin(t * 2.3 + fi * 1.1)
                    let d           = 20.0 * sizeT * rejoinShrink * sizeVar * breathPulse

                    // Elongation: whisper of tangential during orbit; radial pull-in during rejoin.
                    // convergeT ramps up as orbs fall toward center → stretch toward center.
                    let elongFactor = 1.0 + tangElong * 0.07 + convergeT * 0.45
                    // Rotation: tangential during orbit; switch to radial-inward during convergence.
                    let radialInward = angle * (180.0 / .pi)           // points outward (+180 = inward)
                    let tangential   = radialInward + 90.0
                    let rotDeg       = tangential + convergeT * 90.0   // blend to inward radial

                    // Opacity: shimmer while orbiting; stay solid during convergence.
                    let shimmer     = rejoining
                        ? min(1.0, ts * 1.5 + 0.3)                    // solid as they rush in
                        : 0.80 + 0.20 * sin(t * 1.7 + fi * 0.8)

                    Circle()
                        .fill(LinearGradient(colors: [c0, c1],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .overlay(
                            Circle()
                                .fill(RadialGradient(colors: [.white.opacity(0.50), .clear],
                                                     center: .init(x: 0.32, y: 0.28),
                                                     startRadius: 0,
                                                     endRadius: d / 2))
                        )
                        .frame(width: d, height: d)
                        .scaleEffect(x: elongFactor, y: 1.0 / elongFactor)
                        .rotationEffect(.degrees(rotDeg))
                        .shadow(color: c0.opacity(0.65 * min(1.0, orbsT * 2.0)), radius: 8)
                        .offset(x: dx, y: dy)
                        .opacity(min(1.0, orbsT * 3.0) * shimmer)
                }
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
