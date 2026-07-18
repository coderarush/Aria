import Foundation

/// A small spectral "voiceprint" feature vector. This is a BASIC fingerprint (band
/// energies), not a deep speaker-embedding model — good enough to bias toward the
/// owner's voice, not a hard security boundary. Deterministic + pure (testable).
enum VoiceFeatures {
    static let bandCount = 8

    /// Log energy in 8 log-spaced frequency bands, L2-normalized. Empty/too-short
    /// input → a zero vector.
    static func extract(_ samples: [Int16]) -> [Float] {
        guard samples.count >= 16 else { return [Float](repeating: 0, count: bandCount) }
        let n = samples.count
        let x = samples.map { Float($0) / 32768.0 }
        let half = n / 2
        var bands = [Float](repeating: 0, count: bandCount)
        // Naive DFT magnitude (n is one short frame, O(n²) is fine), binned into bands.
        for k in 1..<half {
            var re: Float = 0, im: Float = 0
            let w = -2.0 * Float.pi * Float(k) / Float(n)
            for t in 0..<n {
                let a = w * Float(t)
                re += x[t] * cos(a)
                im += x[t] * sin(a)
            }
            let mag = (re * re + im * im).squareRoot()
            let b = min(bandCount - 1, Int(Float(bandCount) * log2(Float(k) + 1) / log2(Float(half) + 1)))
            bands[b] += mag
        }
        for i in 0..<bandCount { bands[i] = log(1 + bands[i]) }
        let norm = bands.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { for i in 0..<bandCount { bands[i] /= norm } }
        return bands
    }
}

/// Compares voiceprints. Pure math (testable). A real product would use a trained
/// speaker-embedding model; this biases toward the enrolled owner and is deliberately
/// shipped OFF by default and labelled experimental.
enum SpeakerVerifier {
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    static func matches(_ features: [Float], profile: [Float], threshold: Float) -> Bool {
        cosine(features, profile) >= threshold
    }

    /// Element-wise mean of several voiceprints → an enrolled profile.
    static func averaged(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first, !vectors.isEmpty else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == first.count {
            for i in 0..<v.count { sum[i] += v[i] }
        }
        return sum.map { $0 / Float(vectors.count) }
    }
}
