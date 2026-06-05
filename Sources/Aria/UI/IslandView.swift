import SwiftUI

/// Aria's Siri-style presence: a smooth, continuous multi-color glow that hugs the
/// screen edges (one blurred ring, not separate blobs, so it reads as a single
/// combined band of light). The center is transparent and click-through. A bottom
/// caption shows her reply.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @State private var rotate = 0.0
    @State private var breathe = false
    @State private var pulse = false   // v8: springy "pop" on every state change

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

    /// A synthetic, irregular "speech" envelope (~0…1) that makes the orb breathe like
    /// she's talking while she responds. Detuned sines → an organic, non-repeating cadence.
    /// (Stand-in until real TTS playback-amplitude metering lands — tunable on-device.)
    static func speechEnv(_ t: Double) -> Double {
        let e = 0.55 + 0.45 * (0.55 * sin(t * 8.0) + 0.30 * sin(t * 12.7) + 0.15 * sin(t * 5.3))
        return max(0, min(1, e))
    }

    /// Palette for the ring. Looping the first color to the end makes the angular
    /// gradient seamless (no hard seam where it wraps).
    private var palette: [Color] {
        let c = viewModel.glowColors.isEmpty ? [viewModel.accent, viewModel.accent] : viewModel.glowColors
        return c + [c.first ?? viewModel.accent]
    }

    /// Brightness breathes gently and swells with the voice while listening.
    private var intensity: CGFloat {
        let level = viewModel.state == .listening ? CGFloat(min(max(viewModel.audioLevel, 0), 1)) : 0
        return 0.80 + level * 0.40 + (breathe ? 0.12 : 0)
    }

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
            glow
                .opacity(active ? 1 : 0)
                .animation(.easeInOut(duration: 0.55), value: active)
                .allowsHitTesting(false)
            bubbles
                .opacity(active ? 1 : 0)
                .scaleEffect((active ? 1 : 0.6) * (pulse ? 1.07 : 1.0))
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: active)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .bottom) {
            faceOrb
                .opacity(active ? 1 : 0)
                .scaleEffect(active ? 1 : 0.4)
                .padding(.bottom, showCaption ? 178 : 120)
                .animation(.spring(response: 0.55, dampingFraction: 0.6), value: active)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: showCaption)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { rotate = 360 }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onChange(of: viewModel.state) { _, _ in
            // A lively springy pop whenever she changes state (wake, think, answer).
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { pulse = false }
            }
        }
    }

    /// Three concentric blurred strokes of the SAME rotating multi-color gradient,
    /// heavily blurred so they fuse into one smooth, continuous band of light around
    /// the screen edge. The slow rotation makes the colors drift; no discrete blobs.
    private var glow: some View {
        let gradient = AngularGradient(gradient: Gradient(colors: palette),
                                       center: .center, angle: .degrees(rotate))
        return ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(gradient, lineWidth: 96)
                .blur(radius: 90)
                .opacity(0.45 * intensity)
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(gradient, lineWidth: 48)
                .blur(radius: 44)
                .opacity(0.7 * intensity)
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(gradient, lineWidth: 18)
                .blur(radius: 16)
                .opacity(0.9 * intensity)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: intensity)
    }

    /// v8 — Aria's living body: soft multi-color blobs that drift, breathe, and swell
    /// with the voice. A continuous Canvas so it feels organic, not stepped. Heavier
    /// motion while listening/thinking; calm otherwise.
    private var bubbles: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let level = viewModel.state == .listening ? Double(min(max(viewModel.audioLevel, 0), 1)) : 0
            let speaking = viewModel.state == .responding ? Self.speechEnv(t) : 0
            let energy = level + speaking * 0.5   // mic while listening, her voice while talking
            let busy = viewModel.state == .thinking || viewModel.state == .responding
            Canvas { ctx, size in
                let pal = palette
                let count = 9
                for i in 0..<count {
                    let ph = Double(i) * 0.79
                    // Drift along the bottom + sides, orbiting faster while busy.
                    let speed = busy ? 0.55 : 0.28
                    let x = size.width * (0.5 + 0.46 * sin(t * speed + ph))
                    let y = size.height * (0.9 - 0.16 * Double(i % 3)) - sin(t * 0.9 + ph) * 26
                    let pulse = 1 + 0.22 * sin(t * 1.5 + ph) + energy * 0.6
                    let r = (30 + Double(i % 4) * 18) * pulse
                    let c = pal[i % max(pal.count, 1)].opacity((0.30 + energy * 0.35) * Double(intensity))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c))
                }
            }
            .blur(radius: 34)
            .ignoresSafeArea()
        }
    }

    /// v8 — Aria's "face": a small soft orb above the caption that breathes, swells
    /// with the voice, and quickens while thinking. Bottom-anchored, never covers the
    /// user's work.
    private var faceOrb: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let level = viewModel.state == .listening ? Double(min(max(viewModel.audioLevel, 0), 1)) : 0
            let speaking = viewModel.state == .responding ? Self.speechEnv(t) : 0
            let busy = viewModel.state == .thinking
            let s = 1 + 0.07 * sin(t * (busy ? 4.0 : 2.0)) + level * 0.38 + speaking * 0.26
            let c0 = palette.first ?? viewModel.accent
            let c1 = palette.count > 1 ? palette[1] : c0
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.95), c0.opacity(0.78), c1.opacity(0.28)],
                                     center: .init(x: 0.4, y: 0.36), startRadius: 1, endRadius: 28))
                .frame(width: 54, height: 54)
                .scaleEffect(s)
                .shadow(color: c0.opacity(0.32 + speaking * 0.18), radius: 14 + speaking * 8)
        }
        .frame(width: 80, height: 80)
    }

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
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: showCaption)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.responseText)
    }
}
