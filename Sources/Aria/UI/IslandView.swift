import SwiftUI

/// Aria's Siri-style presence: a full-screen animated accent glow hugging the
/// screen edges, plus a bottom caption for her reply. Center is transparent and
/// click-through.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @State private var rotate = 0.0
    @State private var pulse = false

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

    private var glowColors: [Color] {
        let a = viewModel.accent
        return [a.opacity(0.0), a, a.opacity(0.6), .white.opacity(0.5), a, a.opacity(0.0)]
    }

    private var captionText: String {
        switch viewModel.state {
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .responding, .error: return viewModel.responseText
        case .idle: return ""
        }
    }
    private var showCaption: Bool { active && !captionText.isEmpty }

    /// Glow thickens with mic level while listening; steady otherwise.
    private var glowWidth: CGFloat {
        let base: CGFloat = viewModel.state == .listening ? 26 : 18
        let level = viewModel.state == .listening ? CGFloat(viewModel.audioLevel) * 26 : 0
        return base + level + (pulse ? 6 : 0)
    }

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(gradient: Gradient(colors: glowColors),
                                    center: .center, angle: .degrees(rotate)),
                    lineWidth: glowWidth)
                .blur(radius: 32)
                .opacity(active ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: active)
                .animation(.easeInOut(duration: 0.25), value: glowWidth)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if showCaption {
                Text(captionText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(viewModel.accent.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .frame(maxWidth: 680)
                    .padding(.bottom, 90)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.responseText)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { rotate = 360 }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
