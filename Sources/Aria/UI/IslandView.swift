import SwiftUI

/// Aria's Siri-style presence: a soft, breathing accent aurora hugging the
/// screen edges, plus a bottom caption for her reply. The center is transparent
/// and click-through.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    @State private var drift = 0.0       // slow rotation of the gradient
    @State private var breathe = false   // gentle intensity pulse

    private var active: Bool { viewModel.isVisible && viewModel.state != .idle }

    /// Smooth accent band that fades in and out around the ring — two soft lobes,
    /// no harsh stop. Drifts slowly so the glow feels alive, not spinning.
    private var bandColors: [Color] {
        let a = viewModel.accent
        return [a.opacity(0.0), a.opacity(0.5), a, a.opacity(0.5),
                a.opacity(0.0),
                a.opacity(0.5), a, a.opacity(0.5), a.opacity(0.0)]
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

    /// While listening the aurora swells gently with the voice; otherwise it
    /// holds a calm, breathing level.
    private var intensity: CGFloat {
        let level = viewModel.state == .listening ? CGFloat(viewModel.audioLevel) : 0
        return 0.82 + level * 0.38 + (breathe ? 0.12 : 0)
    }

    var body: some View {
        ZStack {
            Color.clear
            glow
                .opacity(active ? 1 : 0)
                .animation(.easeInOut(duration: 0.55), value: active)
        }
        .overlay(alignment: .bottom) { caption }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { drift = 360 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    /// Three layered, blurred strokes give the glow depth: a wide soft halo, a
    /// tighter brighter ring, and a faint white sheen for a glassy edge.
    private var glow: some View {
        let gradient = AngularGradient(gradient: Gradient(colors: bandColors),
                                       center: .center, angle: .degrees(drift))
        return ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .strokeBorder(gradient, lineWidth: 72)
                .blur(radius: 72)
                .opacity(0.5 * intensity)
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .strokeBorder(gradient, lineWidth: 28)
                .blur(radius: 26)
                .opacity(0.9 * intensity)
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 9)
                .blur(radius: 12)
                .opacity(intensity)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: intensity)
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
                    .shadow(color: viewModel.accent.opacity(0.25), radius: 22, y: 8)
                    .frame(maxWidth: 720)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showCaption)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.responseText)
    }
}
