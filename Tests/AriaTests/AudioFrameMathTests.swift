import XCTest
@testable import Aria

final class AudioFrameMathTests: XCTestCase {
    func testFloatToInt16Clamps() {
        XCTAssertEqual(AudioFrameMath.int16(fromFloat: 0), 0)
        XCTAssertEqual(AudioFrameMath.int16(fromFloat: 1.0), 32767)
        XCTAssertEqual(AudioFrameMath.int16(fromFloat: -1.0), -32767)  // symmetric scale
        XCTAssertEqual(AudioFrameMath.int16(fromFloat: 2.0), 32767)    // clamp high
        XCTAssertEqual(AudioFrameMath.int16(fromFloat: -2.0), -32767)  // clamp low
    }

    func testFrameRingEmitsFixedFrames() {
        var ring = FrameRing(frameSize: 4)
        ring.push([1, 2, 3])                 // not enough yet
        XCTAssertNil(ring.pop())
        ring.push([4, 5, 6, 7, 8])           // now 8 samples → two frames of 4
        var frames: [[Int16]] = []
        while let f = ring.pop() { frames.append(f) }
        XCTAssertEqual(frames, [[1, 2, 3, 4], [5, 6, 7, 8]])
    }
}
