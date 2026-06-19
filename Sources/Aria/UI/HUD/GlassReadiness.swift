import Foundation

/// Measures readiness for Glass without hardware (spec §123): surface
/// portability, latency, context quality, presence usefulness.
struct GlassReadiness: Sendable {

    struct Scores: Sendable {
        var portability: Double
        var latency: Double
        var contextQuality: Double
        var presenceUsefulness: Double
    }

    func readiness(_ scores: Scores) -> Double {
        (scores.portability + scores.latency + scores.contextQuality + scores.presenceUsefulness) / 4
    }

    func isReady(_ scores: Scores, threshold: Double = 0.8) -> Bool {
        readiness(scores) >= threshold
    }
}
