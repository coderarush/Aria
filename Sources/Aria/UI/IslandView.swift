import SwiftUI

/// Aria's presence: a single organic, morphing blob anchored bottom-center — a little
/// living creature, not a UI chrome element. It squirms gently while idle/listening,
/// swells with your voice, swirls faster while thinking, and breathes while she speaks.
/// A caption below shows her reply. The rest of the screen stays transparent + click-through.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @State private var pulse = false   // springy "pop" on every state change

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

    /// Blob fill colors (first two of the chosen palette, or the accent).
    private var palette: [Color] {
        let c = viewModel.glowColors.isEmpty ? [viewModel.accent, viewModel.accent] : viewModel.glowColors
        return c
    }

    /// A synthetic, irregular "speech" envelope (~0…1) that makes the blob breathe like
    /// she's talking while she responds. Detuned sines → an organic, non-repeating cadence.
    static func speechEnv(_ t: Double) -> Double {
        let e = 0.55 + 0.45 * (0.55 * sin(t * 8.0) + 0.30 * sin(t * 12.7) + 0.15 * sin(t * 5.3))
        return max(0, min(1, e))
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
            blob
                .opacity(active ? 1 : 0)
                .scaleEffect((active ? 1 : 0.4) * (pulse ? 1.06 : 1.0))
                .padding(.bottom, showCaption ? 134 : 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(.spring(response: 0.55, dampingFraction: 0.62), value: active)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: showCaption)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: pulse)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { caption }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.state) { _, _ in
            // A lively springy pop whenever she changes state (wake, think, answer).
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
        }
    }

    /// The morphing blob. A continuous Canvas-like TimelineView feeds fresh vertex radii
    /// each frame so the outline squirms organically; reaction comes from how much it
    /// wobbles (amp) and how fast (speed).
    private var blob: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let level = viewModel.state == .listening ? Double(min(max(viewModel.audioLevel, 0), 1)) : 0
            let speaking = viewModel.state == .responding ? Self.speechEnv(t) : 0
            let thinking = viewModel.state == .thinking
            // Calm + nearly round when idle (top-left look); amoeba-wobbly when busy.
            let amp = 0.07 + level * 0.16 + speaking * 0.12 + (thinking ? 0.07 : 0)
            let speed = thinking ? 1.8 : 1.0
            let envScale = 1 + level * 0.12 + speaking * 0.10
            let radii = BlobMath.radii(t: t, n: 11, amp: amp, speed: speed)
            let c0 = palette.first ?? viewModel.accent
            let c1 = palette.count > 1 ? palette[1] : c0

            BlobShape(radii: radii)
                .fill(LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    // Soft inner highlight so it reads as a rounded, gel-like body.
                    BlobShape(radii: radii)
                        .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                             center: .init(x: 0.38, y: 0.30), startRadius: 1, endRadius: 62))
                )
                .frame(width: 150, height: 150)
                .scaleEffect(envScale)
                // Solid, gel-like body — just a soft depth shadow + a faint color halo,
                // not the big glow from before.
                .shadow(color: .black.opacity(0.22), radius: 10, y: 7)
                .shadow(color: c0.opacity(0.28), radius: 16)
        }
        .frame(width: 184, height: 184)
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
