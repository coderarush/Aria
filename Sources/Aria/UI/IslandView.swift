import SwiftUI

/// Aria's Siri-style presence: a smooth, continuous multi-color glow that hugs the
/// screen edges (one blurred ring, not separate blobs, so it reads as a single
/// combined band of light). The center is transparent and click-through. A bottom
/// caption shows her reply.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @State private var rotate = 0.0
    @State private var breathe = false

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

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
        }
        .overlay(alignment: .bottom) { caption }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { rotate = 360 }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
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
