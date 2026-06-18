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
        await locateScored(description, gemini: gemini, screen: screen)?.point
    }

    /// Like `locate`, but also returns the model's self-reported confidence (0…1) so the
    /// caller can refuse to click a low-confidence guess. Confidence is the model's own
    /// estimate — treat it as a soft signal, not ground truth.
    static func locateScored(_ description: String,
                             gemini: GeminiClient = GeminiClient(),
                             screen: ScreenCaptureEngine = ScreenCaptureEngine()) async -> (point: CGPoint, confidence: Double)? {
        guard let jpeg = try? await screen.capturePrimaryJPEG() else { return nil }
        let prompt = """
        Find this on-screen UI element: "\(description)".
        Reply with ONLY a JSON object giving the element's CENTER as fractions of the \
        image size (0.0–1.0 from the top-left) and your confidence (0.0–1.0) that this is \
        the right element: {"x":0.42,"y":0.13,"confidence":0.8}. If it isn't visible, \
        reply {"found":false}.
        """
        let raw = (try? await gemini.generateTextWithImage(prompt: prompt, jpeg: jpeg)) ?? ""
        guard let frac = parseFraction(raw) else { return nil }
        let conf = parseConfidence(raw)
        let point = await MainActor.run { screenPoint(fromFraction: frac) }
        return (point, conf)
    }

    /// Parse an optional "confidence":0–1 from the vision reply; defaults to a cautious
    /// 0.55 when the model omits it (a bare point is a guess we shouldn't over-trust).
    static func parseConfidence(_ raw: String) -> Double {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let sliced = JSONSlice.between(cleaned, open: "{", close: "}"),
              let data = sliced.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = (obj["confidence"] as? NSNumber)?.doubleValue, (0...1).contains(c) else {
            return 0.55
        }
        return c
    }

    /// Parse {"x":..,"y":..} fractions; nil on {"found":false} or garbage.
    static func parseFraction(_ raw: String) -> CGPoint? {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let sliced = JSONSlice.between(cleaned, open: "{", close: "}"),
              let data = sliced.data(using: .utf8),
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
