import XCTest
@testable import Aria

final class UISoundsTests: XCTestCase {

    /// Every cue *except* the deliberately near-silent caption tick must be
    /// hearable but stay subtle.
    func testAudibleChimesHaveHearableLengthAndHeadroom() {
        for kind in UISounds.Kind.allCases where kind != .tick {
            let pcm = UISounds.pcm(for: kind)
            let secs = Double(pcm.count) / UISounds.sampleRate
            XCTAssertGreaterThan(secs, 0.08, "\(kind) too short to hear")
            XCTAssertLessThan(secs, 0.6, "\(kind) too long — must stay subtle")
            let peak = pcm.map { abs(Int($0)) }.max() ?? 0
            XCTAssertGreaterThan(peak, 1500, "\(kind) inaudible")
            XCTAssertLessThan(peak, 12000, "\(kind) too loud for an ambient cue")
        }
    }

    /// The per-word caption tick is intentionally a micro-cue (amp 0.04, ~25ms):
    /// audible but quieter and briefer than every other sound, by design.
    func testCaptionTickIsBriefAndNearSilent() {
        let pcm = UISounds.pcm(for: .tick)
        XCTAssertFalse(pcm.isEmpty)
        let secs = Double(pcm.count) / UISounds.sampleRate
        XCTAssertLessThan(secs, 0.08, "tick should be a micro-cue, not a chime")
        let peak = pcm.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 200, "tick still must produce sound")
        XCTAssertLessThan(peak, 1500, "tick must stay quieter than audible cues")
    }

    func testChimesStartAndEndNearSilence() {
        for kind in UISounds.Kind.allCases {
            let pcm = UISounds.pcm(for: kind)
            XCTAssertLessThan(abs(Int(pcm.first ?? 0)), 200, "\(kind) clicks at start")
            XCTAssertLessThan(abs(Int(pcm.last ?? 0)), 400, "\(kind) clicks at end")
        }
    }

    func testDeterministic() {
        XCTAssertEqual(UISounds.pcm(for: .wake), UISounds.pcm(for: .wake))
    }

    /// Source of truth is `Kind.allCases` — no hardcoded count. Every kind must
    /// render a non-empty, unique waveform.
    func testEveryKindIsDistinctAndNonEmpty() {
        let kinds = UISounds.Kind.allCases
        var seen: [[Int16]] = []
        for kind in kinds {
            let pcm = UISounds.pcm(for: kind)
            XCTAssertFalse(pcm.isEmpty, "\(kind) produced no audio")
            XCTAssertFalse(seen.contains(pcm), "\(kind) duplicates another cue")
            seen.append(pcm)
        }
        XCTAssertEqual(seen.count, kinds.count)
    }

    func testWavDataIsPlayableSize() {
        let data = UISounds.wavData(for: .done)
        XCTAssertGreaterThan(data.count, 44, "must contain a WAV header + samples")
    }
}
