import SwiftUI

/// Aria's brand mark, distilled into the main window. Reuses the very same
/// `BlobShape` + `BlobMath` that draw the live orb (see MorphingBlobView /
/// IslandView) so the app and the orb are unmistakably the same creature — just
/// calmer here. Two modes:
///   • `animated: false` — a still, gently-wobbled blob for the sidebar logo and
///     small chrome (cheap, no TimelineView).
///   • `animated: true`  — a slow breathing hero for the Home overview + empty
///     states, driven by `.animation` ticks exactly like the orb.
///
/// Colors come straight from the user's chosen accent + glow palette, so the mark
/// always matches their orb.
struct AppBlobMark: View {
    var size: CGFloat = 28
    var animated: Bool = false

    @ObservedObject private var settings = AppSettings.shared

    private var palette: [Color] {
        let colors = Theme.glowColors(id: settings.glowPaletteID, accent: settings.accentColor)
        return colors.isEmpty ? [settings.accentColor, settings.accentColor] : colors
    }

    var body: some View {
        Group {
            // Honor Reduce Motion; and a slow breathe needs 30 fps, not the
            // display's 120 — quarter the render work for identical feel.
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let breathe = 0.5 + 0.5 * sin(t * 1.2)
                    let amp = 0.085 + breathe * 0.045
                    body(radii: BlobMath.radii(t: t, n: 11, amp: amp, speed: 0.7),
                         scale: 1 + breathe * 0.035)
                }
            } else {
                // A fixed, pleasant frame — no animation cost in lists/sidebar.
                body(radii: BlobMath.radii(t: 2.1, n: 11, amp: 0.1, speed: 1), scale: 1)
            }
        }
        .frame(width: size, height: size)
    }

    private func body(radii: [CGFloat], scale: CGFloat) -> some View {
        let c0 = palette.first ?? settings.accentColor
        let c1 = palette.count > 1 ? palette[1] : c0
        return BlobShape(radii: radii)
            .fill(LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                BlobShape(radii: radii)
                    .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                         center: .init(x: 0.38, y: 0.30),
                                         startRadius: 1, endRadius: size * 0.42))
            )
            .scaleEffect(scale)
            .shadow(color: .black.opacity(0.18), radius: size * 0.07, y: size * 0.04)
            .shadow(color: c0.opacity(0.30), radius: size * 0.16)
    }
}
