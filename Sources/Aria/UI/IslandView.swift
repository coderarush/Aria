import SwiftUI

/// The Dynamic-Island pill. One surface whose size/content morph by state.
/// Pinned at the top; grows downward. Color appears only on accents; the
/// surface stays neutral `.ultraThinMaterial`.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    private var size: CGSize {
        switch viewModel.state {
        case .idle:       return CGSize(width: 200, height: 34)
        case .listening:  return CGSize(width: 320, height: 64)
        case .thinking:   return CGSize(width: 320, height: 64)
        case .responding, .error: return CGSize(width: 380, height: 140)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(viewModel.accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

            content
                .padding(.horizontal, 16)
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.state)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onTapGesture { if viewModel.state == .responding || viewModel.state == .error { viewModel.dismiss() } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle:
            BreathingDot(accent: viewModel.accent)
        case .listening:
            WaveformView(level: viewModel.audioLevel, color: viewModel.accent)
                .frame(height: 28)
        case .thinking:
            ShimmerBar(accent: viewModel.accent)
        case .responding, .error:
            Text(viewModel.responseText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Faint accent dot that breathes while idle.
private struct BreathingDot: View {
    let accent: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(accent.opacity(on ? 0.8 : 0.3))
            .frame(width: 6, height: 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Indeterminate accent shimmer sweep for the thinking state.
private struct ShimmerBar: View {
    let accent: Color
    @State private var x: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [.clear, accent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * 0.4, height: 4)
                .offset(x: x * geo.size.width)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { x = 1 }
                }
        }
        .frame(height: 8)
    }
}
