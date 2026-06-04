import XCTest
@testable import Aria

final class BargeControllerTests: XCTestCase {
    private func frame(_ amp: Int16) -> [Int16] { [Int16](repeating: amp, count: 160) }

    func testFiresOnSustainedSpeechWhilePlaying() {
        var fired = false
        let bc = BargeController(onsetFrames: 3, energyThreshold: 500)
        bc.onBarge = { fired = true }
        bc.setPlaying(true)
        bc.feed(frame(2000)); bc.feed(frame(2000)); XCTAssertFalse(fired) // 2 < 3
        bc.feed(frame(2000)); XCTAssertTrue(fired)                        // 3rd → barge
    }

    func testSilentFramesDoNotFire() {
        var fired = false
        let bc = BargeController(onsetFrames: 3, energyThreshold: 500)
        bc.onBarge = { fired = true }
        bc.setPlaying(true)
        for _ in 0..<10 { bc.feed(frame(10)) }   // below threshold
        XCTAssertFalse(fired)
    }

    func testDoesNotFireWhenNotPlaying() {
        var fired = false
        let bc = BargeController(onsetFrames: 1, energyThreshold: 500)
        bc.onBarge = { fired = true }
        bc.setPlaying(false)
        bc.feed(frame(5000))
        XCTAssertFalse(fired)   // only barge DURING Aria's speech
    }

    func testFiresOnlyOncePerUtterance() {
        var count = 0
        let bc = BargeController(onsetFrames: 1, energyThreshold: 500)
        bc.onBarge = { count += 1 }
        bc.setPlaying(true)
        bc.feed(frame(5000)); bc.feed(frame(5000)); bc.feed(frame(5000))
        XCTAssertEqual(count, 1)   // one barge, not three
    }
}
