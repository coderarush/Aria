import Foundation

/// Aria's interaction sounds — tiny synthesized chimes, generated in code so
/// there are no asset files and the character is exactly hers: soft sine tones
/// with gentle attack/decay, quiet enough to feel ambient. Played through
/// `AudioBus.playReference` so the echo canceller subtracts them from the mic
/// and they can never pollute recognition or trigger barge-in.
enum UISounds {
    static let sampleRate: Double = 24_000

    enum Kind: CaseIterable {
        /// She started listening (wake word / ⌥Space): two soft notes, rising.
        case wake
        /// A task finished: one warm note, settling down.
        case done
        /// She's deploying into a longer multi-step task: a purposeful
        /// three-note ascent — "rolling up sleeves".
        case task
        /// Something failed: a gentle low double-tap, never alarming.
        case error
    }

    /// 16-bit mono PCM at `sampleRate`. Deterministic.
    static func pcm(for kind: Kind) -> [Int16] {
        switch kind {
        case .wake:
            // A5 → E6, short and airy.
            return note(freq: 880, secs: 0.09, amp: 0.16)
                 + note(freq: 1318.5, secs: 0.14, amp: 0.14)
        case .done:
            // E6 → A5 settle, slightly longer tail.
            return note(freq: 1318.5, secs: 0.08, amp: 0.13)
                 + note(freq: 880, secs: 0.18, amp: 0.15)
        case .task:
            // A5 → C#6 → E6 — a small major arpeggio, things are happening.
            return note(freq: 880, secs: 0.07, amp: 0.13)
                 + note(freq: 1108.7, secs: 0.07, amp: 0.13)
                 + note(freq: 1318.5, secs: 0.16, amp: 0.14)
        case .error:
            // Two soft low E4 taps — informative, not punitive.
            return note(freq: 329.6, secs: 0.09, amp: 0.15)
                 + note(freq: 329.6, secs: 0.14, amp: 0.12)
        }
    }

    static func wavData(for kind: Kind) -> Data {
        let samples = pcm(for: kind)
        var data = Data(capacity: samples.count * 2)
        for s in samples {
            var le = s.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return VoiceEngine.wavData(fromPCM: data, sampleRate: Int(sampleRate))
    }

    /// One sine note with a fast attack and exponential release — no clicks.
    private static func note(freq: Double, secs: Double, amp: Double) -> [Int16] {
        let n = Int(secs * sampleRate)
        var out = [Int16](repeating: 0, count: n)
        let attack = max(1, Int(0.012 * sampleRate))
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env: Double
            if i < attack {
                env = Double(i) / Double(attack)
            } else {
                let rel = Double(i - attack) / Double(max(1, n - attack))
                env = exp(-3.2 * rel)
            }
            let v = sin(2 * .pi * freq * t) * env * amp
            out[i] = Int16(max(-1, min(1, v)) * 32_000)
        }
        // Hard-zero the final samples so back-to-back notes can't click.
        if n > 8 { for i in (n - 8)..<n { out[i] = Int16(Double(out[i]) * Double(n - 1 - i) / 8.0) } }
        return out
    }
}
