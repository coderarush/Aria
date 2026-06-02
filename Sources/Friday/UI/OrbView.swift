import SwiftUI

/// The floating orb. SwiftUI gradient + blur + glow (Metal shaders deferred to a
/// later pass). Materializes with a spring, shows a waveform while listening, a
/// rotating arc while thinking, and a response card while responding. Draggable.
struct OrbView: View {
    @ObservedObject var viewModel: OrbViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var accumulated: CGSize = .zero
    @State private var breathe = false
    @State private var arcRotation = 0.0
    @State private var flash = false

    private let orbSize: CGFloat = 84

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.state == .responding || viewModel.state == .error,
               !viewModel.responseText.isEmpty {
                ResponseCard(text: viewModel.responseText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            orb
                .scaleEffect(viewModel.isVisible ? 1 : 0.1)
                .opacity(viewModel.isVisible ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: viewModel.isVisible)
                .modifier(ShakeEffect(animatableData: viewModel.state == .error ? 1 : 0))
        }
        .offset(x: accumulated.width + dragOffset.width,
                y: accumulated.height + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { _ in
                    accumulated.width += dragOffset.width
                    accumulated.height += dragOffset.height
                    dragOffset = .zero
                }
        )
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
        .onChange(of: viewModel.state) { _ in syncAnimations() }
        .onAppear { syncAnimations() }
    }

    // MARK: Orb

    private var orb: some View {
        ZStack {
            // Outer glow.
            Circle()
                .fill(stateColor)
                .frame(width: orbSize * 1.5, height: orbSize * 1.5)
                .blur(radius: 28)
                .opacity(0.45)

            // Glass body.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [stateColor.opacity(0.95), stateColor.opacity(0.55)],
                        center: .topLeading, startRadius: 4, endRadius: orbSize)
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.35), lineWidth: 1)
                )
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(breathe && viewModel.state == .listening ? 1.06 : 1.0)
                .shadow(color: stateColor.opacity(0.6), radius: 16)

            // Thinking arc.
            if viewModel.state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AngularGradient(colors: [.clear, stateColor, .white], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: orbSize + 14, height: orbSize + 14)
                    .rotationEffect(.degrees(arcRotation))
            }

            // Listening waveform ring.
            if viewModel.state == .listening {
                WaveformView(level: viewModel.audioLevel, color: .white)
                    .frame(width: orbSize, height: orbSize)
            }

            // Screenshot flash.
            Circle()
                .fill(.white)
                .frame(width: orbSize, height: orbSize)
                .opacity(flash ? 0.8 : 0)
        }
    }

    // MARK: State → visuals

    private var stateColor: Color {
        switch viewModel.state {
        case .listening: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .thinking:  return Color(red: 1.0, green: 0.78, blue: 0.3)
        case .acting:    return Color(red: 0.6, green: 0.5, blue: 1.0)
        case .responding: return Color(red: 0.3, green: 0.85, blue: 0.55)
        case .error:     return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .hidden:    return .gray
        }
    }

    private func syncAnimations() {
        breathe = false
        if viewModel.state == .listening {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        if viewModel.state == .thinking {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                arcRotation = 360
            }
        } else {
            arcRotation = 0
        }
    }

    /// Trigger the screenshot flash from outside (called when capture fires).
    func triggerFlash() {
        flash = true
        withAnimation(.easeOut(duration: 0.4)) { flash = false }
    }
}

/// Gentle horizontal shake for the error state.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
