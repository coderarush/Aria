import SwiftUI

/// Observable state for one Lens pass — the strokes the user is drawing on screen
/// and the visual palette to render them in. Deliberately tiny: the heavy lifting
/// (capture → vision) lives in the controller; this only drives the canvas.
@MainActor
final class LensSession: ObservableObject {
    /// `explain` = circle one thing, Aria reads it and answers (one stroke, then
    /// done). `draw` = freeform annotation that stays on screen (many strokes),
    /// the way you'd scribble on a shared screen.
    enum Mode { case explain, draw }

    let mode: Mode
    /// Completed strokes (draw mode keeps several; explain mode keeps one).
    @Published var strokes: [[CGPoint]] = []
    /// The stroke currently under the cursor.
    @Published var current: [CGPoint] = []

    let accent: Color
    let glow: [Color]

    init(mode: Mode, accent: Color, glow: [Color]) {
        self.mode = mode
        self.accent = accent
        self.glow = glow.isEmpty ? [accent] : glow
    }

    /// The blob colors to tint ink with — accent first so single-color themes look
    /// intentional, not washed out.
    var palette: [Color] { glow }
}
