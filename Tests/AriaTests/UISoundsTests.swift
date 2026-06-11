import XCTest
@testable import Aria

final class UISoundsTests: XCTestCase {

    func testChimesHaveExpectedLengthAndHeadroom() {
        for kind in UISounds.Kind.allCases {
            let pcm = UISounds.pcm(for: kind)
            let secs = Double(pcm.count) / UISounds.sampleRate
            XCTAssertGreaterThan(secs, 0.08, "\(kind) too short to hear")
            XCTAssertLessThan(secs, 0.6, "\(kind) too long — must stay subtle")
            let peak = pcm.map { abs(Int($0)) }.max() ?? 0
            XCTAssertGreaterThan(peak, 1500, "\(kind) inaudible")
            XCTAssertLessThan(peak, 12000, "\(kind) too loud for an ambient cue")
        }
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

    func testAllFourKindsExistAndDiffer() {
        XCTAssertEqual(UISounds.Kind.allCases.count, 4)
        XCTAssertNotEqual(UISounds.pcm(for: .task), UISounds.pcm(for: .wake))
        XCTAssertNotEqual(UISounds.pcm(for: .error), UISounds.pcm(for: .done))
    }

    func testWavDataIsPlayableSize() {
        let data = UISounds.wavData(for: .done)
        XCTAssertGreaterThan(data.count, 44, "must contain a WAV header + samples")
    }
}
