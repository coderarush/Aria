import SwiftUI

/// Animated ring of bars around the orb showing live mic input level.
struct WaveformView: View {
    var level: Float
    var color: Color

    private let barCount = 28

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            ZStack {
                ForEach(0..<barCount, id: \.self) { i in
                    bar(index: i, radius: radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func bar(index: Int, radius: CGFloat) -> some View {
        let angle = Double(index) / Double(barCount) * 2 * .pi
        // Pseudo-random per-bar variation so the ring feels alive.
        let variation = (sin(Double(index) * 1.7) + 1) / 2
        let height = 4 + CGFloat(level) * 18 * CGFloat(0.4 + variation)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.85))
            .frame(width: 3, height: height)
            .offset(y: -radius - 6)
            .rotationEffect(.radians(angle))
            .animation(.easeOut(duration: 0.12), value: level)
    }
}
