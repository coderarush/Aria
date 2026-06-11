import XCTest
import AVFoundation
@testable import Aria

final class AudioPlayableTests: XCTestCase {

    private func sine(_ n: Int) -> Data {
        var d = Data(capacity: n * 2)
        for i in 0..<n {
            var s = Int16(sin(Double(i) * 0.1) * 8000).littleEndian
            withUnsafeBytes(of: &s) { d.append(contentsOf: $0) }
        }
        return d
    }

    func testConvertsMonoInt16ToStereoFloatNodeFormat() throws {
        // The exact mismatch that crashed live: 24k mono Int16 PCM scheduled on a
        // node connected as 48k stereo Float32 — must convert, never throw.
        let node = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buf = AudioBus.playableBuffer(pcm: sine(2400), pcmRate: 24_000, nodeFormat: node)
        let out = try XCTUnwrap(buf)
        XCTAssertEqual(out.format.channelCount, 2)
        XCTAssertEqual(out.format.sampleRate, 48_000)
        XCTAssertGreaterThan(out.frameLength, 4000, "0.1s at 48k ≈ 4800 frames")
    }

    func testPassesThroughWhenFormatsAlreadyMatch() throws {
        let node = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                 channels: 1, interleaved: true)!
        let buf = try XCTUnwrap(AudioBus.playableBuffer(pcm: sine(2400), pcmRate: 24_000, nodeFormat: node))
        XCTAssertEqual(buf.format.sampleRate, 24_000)
        XCTAssertEqual(buf.frameLength, 2400)
    }

    func testEmptyPCMYieldsNil() {
        let node = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        XCTAssertNil(AudioBus.playableBuffer(pcm: Data(), pcmRate: 24_000, nodeFormat: node))
    }
}
