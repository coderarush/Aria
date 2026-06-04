import XCTest
@testable import Aria

final class SpeakerVerifierTests: XCTestCase {
    func testCosineIdenticalIsOne() {
        let v: [Float] = [0.1, 0.2, 0.3, 0.4]
        XCTAssertEqual(SpeakerVerifier.cosine(v, v), 1.0, accuracy: 1e-5)
    }
    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(SpeakerVerifier.cosine([1, 0], [0, 1]), 0, accuracy: 1e-6)
    }
    func testMatchesThreshold() {
        let a: [Float] = [1, 0, 0]
        let near: [Float] = [0.95, 0.1, 0.05]
        XCTAssertTrue(SpeakerVerifier.matches(near, profile: a, threshold: 0.8))
        XCTAssertFalse(SpeakerVerifier.matches([0, 1, 0], profile: a, threshold: 0.8))
    }
    func testAveragedIsElementwiseMean() {
        let avg = SpeakerVerifier.averaged([[0, 2, 4], [2, 4, 8]])
        XCTAssertEqual(avg, [1, 3, 6])
    }

    func testFeaturesAreDeterministicFixedLength() {
        let samples = (0..<160).map { Int16(2000 * sin(Double($0) * 0.3)) }
        let f1 = VoiceFeatures.extract(samples)
        let f2 = VoiceFeatures.extract(samples)
        XCTAssertEqual(f1.count, VoiceFeatures.bandCount)
        XCTAssertEqual(f1, f2)                          // deterministic
        XCTAssertGreaterThan(f1.reduce(0, +), 0)        // non-trivial
    }

    func testDifferentTonesDifferentFingerprints() {
        let low = (0..<160).map { Int16(3000 * sin(Double($0) * 0.10)) }
        let high = (0..<160).map { Int16(3000 * sin(Double($0) * 0.80)) }
        XCTAssertLessThan(SpeakerVerifier.cosine(VoiceFeatures.extract(low), VoiceFeatures.extract(high)), 0.99)
    }
}
