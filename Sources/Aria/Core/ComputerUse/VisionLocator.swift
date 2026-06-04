import Foundation
import CoreGraphics
import AppKit

/// The vision fallback for computer use: when the Accessibility tree can't find a
/// control (Electron, canvas, custom-drawn UIs), screenshot the screen, ask a
/// multimodal model where the element is (as a fraction of the image), and convert
/// that to a screen point to click. Gemini-only (vision); used sparingly, so it stays
/// cheap on the free tier.
enum VisionLocator {
    /// Locate `description` on screen; returns a clickable point (CGEvent/top-left
    /// coordinate space) or nil if not found / vision unavailable.
    static func locate(_ description: String,
                       gemini: GeminiClient = GeminiClient(),
                       screen: ScreenCaptureEngine = ScreenCaptureEngine()) async -> CGPoint? {
        guard let jpeg = try? await screen.capturePrimaryJPEG() else { return nil }
        let prompt = """
        Find this on-screen UI element: "\(description)".
        Reply with ONLY a JSON object giving the element's CENTER as fractions of the \
        image size (0.0–1.0 from the top-left): {"x":0.42,"y":0.13}. If it isn't \
        visible, reply {"found":false}.
        """
        let raw = (try? await gemini.generateTextWithImage(prompt: prompt, jpeg: jpeg)) ?? ""
        guard let frac = parseFraction(raw) else { return nil }
        return await MainActor.run { screenPoint(fromFraction: frac) }
    }

    /// Parse {"x":..,"y":..} fractions; nil on {"found":false} or garbage.
    static func parseFraction(_ raw: String) -> CGPoint? {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let found = obj["found"] as? Bool, !found { return nil }
        guard let x = (obj["x"] as? NSNumber)?.doubleValue, let y = (obj["y"] as? NSNumber)?.doubleValue,
              (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Fraction (0–1) of the main display → a top-left global screen point (CGEvent space).
    @MainActor static func screenPoint(fromFraction f: CGPoint) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())   // points, top-left origin
        return CGPoint(x: bounds.origin.x + f.x * bounds.width,
                       y: bounds.origin.y + f.y * bounds.height)
    }
}
