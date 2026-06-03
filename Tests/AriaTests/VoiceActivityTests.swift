import XCTest
@testable import Aria

final class VoiceActivityTests: XCTestCase {
    func testDetectsSpeechOnsetAfterDebounce() {
        var vad = VoiceActivity(threshold: 0.1, onsetFrames: 3, hangoverFrames: 5)
        XCTAssertFalse(vad.process(0.02).isSpeaking)
        _ = vad.process(0.5); _ = vad.process(0.5)
        XCTAssertTrue(vad.process(0.5).isSpeaking)
    }

    func testEndpointsAfterHangoverSilence() {
        var vad = VoiceActivity(threshold: 0.1, onsetFrames: 1, hangoverFrames: 2)
        XCTAssertTrue(vad.process(0.5).isSpeaking)
        _ = vad.process(0.0)
        let r = vad.process(0.0)
        XCTAssertFalse(r.isSpeaking)
        XCTAssertTrue(r.didEndpoint)
    }
}
