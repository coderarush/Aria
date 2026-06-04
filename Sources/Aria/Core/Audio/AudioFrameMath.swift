import Foundation

enum AudioFrameMath {
    static func int16(fromFloat f: Float) -> Int16 {
        let scaled = max(-1, min(1, f)) * 32767
        return Int16(scaled.rounded())
    }
    static func int16s(fromFloats f: [Float]) -> [Int16] { f.map(int16(fromFloat:)) }
}

/// Accumulates Int16 samples and hands them out in fixed-size frames, buffering the
/// remainder. Turns variable-size audio taps into the AEC's fixed frames.
struct FrameRing {
    let frameSize: Int
    private var buf: [Int16] = []
    init(frameSize: Int) { self.frameSize = frameSize }
    mutating func push(_ samples: [Int16]) { buf.append(contentsOf: samples) }
    mutating func pop() -> [Int16]? {
        guard buf.count >= frameSize else { return nil }
        let frame = Array(buf.prefix(frameSize))
        buf.removeFirst(frameSize)
        return frame
    }
}
