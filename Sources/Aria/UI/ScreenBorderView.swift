import SwiftUI

/// Aria living on the screen's edge as a Siri-style soft glow: layered, heavily
/// blurred bands of her palette that slowly rotate around the perimeter, with a
/// few brighter light-pools drifting along the rim. Luminous and ambient — not a
/// crisp ring, not beads. While listening and while executing a task, this is her.
///
/// All geometry comes from `BorderMath`; this view only paints. It is purely
/// decorative and click-through — it never intercepts mouse events.
struct ScreenBorderView: View {
    /// Brand palette (hues are derived from the first colors).
    var palette: [Color]
    /// Master opacity 0…1 — the choreographer drains this during consolidate and
    /// ramps it on wake / splash-ignite.
    var intensity: Double
    /// Splash-ignition gate. `nil` = full ring. Otherwise only the arc within
    /// `phase·0.5` of bottom-center (u = 0.5) is revealed, spreading both ways 0→1.
    var sweepPhase: Double?

    private let inset: CGFloat = 6
    private let cornerRadius: CGFloat = 28

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                if intensity > 0.001 {
                    glow(t: t, size: geo.size)
                        .opacity(intensity)
                        .mask(revealMask(size: geo.size))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - The composited glow

    private func glow(t: Double, size: CGSize) -> some View {
        let h = hues()
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        return ZStack {
            // 1. Primary conic band — slow clockwise drift (~50s / rev).
            conicBand(colors: cyclic(h), angle: t * 7, lineWidth: 96, blur: 50, opacity: 0.34)
            // 2. Counter-rotating band — different hue order, softer, for shimmer/depth.
            conicBand(colors: cyclic(h.reversed()), angle: -t * 5, lineWidth: 70, blur: 66, opacity: 0.22)
            // 3. Drifting light-pools riding the rim — the moving "energy".
            ForEach(0..<4, id: \.self) { i in
                lightPool(hue: h[i % h.count], u: pool_u(i, t), rect: rect)
            }
        }
        .compositingGroup()
        .blendMode(.plusLighter)
    }

    /// An inset rounded-rect drawn as a thick, heavily-blurred conic-gradient band.
    private func conicBand(colors: [Color], angle: Double, lineWidth: CGFloat,
                           blur: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: inset)
            .strokeBorder(
                AngularGradient(gradient: Gradient(colors: colors), center: .center,
                                angle: .degrees(angle)),
                lineWidth: lineWidth)
            .blur(radius: blur)
            .opacity(opacity)
    }

    /// A big soft radial glow positioned on the perimeter at parameter `u`.
    private func lightPool(hue: Color, u: Double, rect: CGRect) -> some View {
        let p = BorderMath.point(u: u, in: rect, cornerRadius: cornerRadius).point
        return RadialGradient(gradient: Gradient(colors: [hue.opacity(0.7), hue.opacity(0)]),
                              center: .center, startRadius: 2, endRadius: 150)
            .frame(width: 300, height: 300)
            .blur(radius: 44)
            .opacity(0.3)
            .position(p)
    }

    /// Each pool advances around the rim at its own slow pace from its own start.
    private func pool_u(_ i: Int, _ t: Double) -> Double {
        let base = Double(i) / 4.0
        let speed = 0.011 + 0.004 * Double(i)        // ~0.011…0.023 laps/sec (~43–90s/lap)
        let u = base + t * speed
        return u - floor(u)
    }

    // MARK: - Splash-ignite reveal

    /// Full white = whole ring visible. During ignite, a thick perimeter arc grows
    /// from bottom-center (u = 0.5) outward, revealing the glow as it spreads.
    @ViewBuilder
    private func revealMask(size: CGSize) -> some View {
        if let phase = sweepPhase {
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            ArcRevealShape(rect: rect, cornerRadius: cornerRadius, halfWidthU: max(0, phase) * 0.5)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 320, lineCap: .round, lineJoin: .round))
                .blur(radius: 24)
        } else {
            Rectangle().fill(Color.white)
        }
    }

    // MARK: - Palette helpers

    /// Up to three brand hues; if the palette is monochrome, fan it out a little so
    /// the conic gradient still has flow.
    private func hues() -> [Color] {
        let base = palette.isEmpty ? [Color.accentColor] : palette
        if base.count >= 3 { return Array(base.prefix(3)) }
        if base.count == 2 { return [base[0], blend(base[0], base[1], 0.5), base[1]] }
        let c = base[0]
        return [shift(c, brightness: 0.12), c, shift(c, brightness: -0.12)]
    }

    /// Close the loop so the conic gradient wraps seamlessly (0° == 360°).
    private func cyclic(_ c: [Color]) -> [Color] { c + [c.first ?? .accentColor] }

    private func shift(_ c: Color, brightness db: CGFloat) -> Color {
        #if canImport(AppKit)
        let n = (NSColor(c).usingColorSpace(.deviceRGB)) ?? .white
        var hh: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        n.getHue(&hh, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(hh), saturation: Double(s),
                     brightness: Double(min(1, max(0, b + db))), opacity: Double(a))
        #else
        return c
        #endif
    }

    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        #if canImport(AppKit)
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        let f = CGFloat(t)
        return Color(red: Double(na.redComponent + (nb.redComponent - na.redComponent) * f),
                     green: Double(na.greenComponent + (nb.greenComponent - na.greenComponent) * f),
                     blue: Double(na.blueComponent + (nb.blueComponent - na.blueComponent) * f))
        #else
        return t < 0.5 ? a : b
        #endif
    }
}

/// A perimeter arc centered on bottom-center (u = 0.5), spanning ±`halfWidthU` in
/// perimeter-parameter units. Used as the growing reveal mask during splash-ignite.
private struct ArcRevealShape: Shape {
    let rect: CGRect
    let cornerRadius: CGFloat
    let halfWidthU: Double

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard halfWidthU > 0 else { return path }
        let steps = 120
        let lo = 0.5 - halfWidthU, hi = 0.5 + halfWidthU
        for i in 0...steps {
            let u = lo + (hi - lo) * Double(i) / Double(steps)
            let p = BorderMath.point(u: u, in: rect, cornerRadius: cornerRadius).point
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}
