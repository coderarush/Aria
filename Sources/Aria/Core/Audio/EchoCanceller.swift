import Foundation
import CSpeexDSP

/// Swift wrapper over speexdsp's MDF acoustic echo canceller. Feed it the near-end
/// (mic) and the far-end (what we're playing — Aria's TTS) in matched frames; get
/// back the near-end with the echo removed. Not thread-safe; the owner (AudioBus)
/// drives it from one audio queue.
final class EchoCanceller {
    private let frameSize: Int
    private var state: OpaquePointer?      // SpeexEchoState*
    private var preprocess: OpaquePointer? // SpeexPreprocessState*

    init(frameSize: Int = 160, filterTaps: Int = 160 * 16, sampleRate: Int = 16000) {
        self.frameSize = frameSize
        state = speex_echo_state_init(Int32(frameSize), Int32(filterTaps))
        var rate = Int32(sampleRate)
        _ = speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate)
        preprocess = speex_preprocess_state_init(Int32(frameSize), Int32(sampleRate))
        // Hand the echo state to the preprocessor so it can suppress residual echo.
        if let s = state {
            _ = speex_preprocess_ctl(preprocess, SPEEX_PREPROCESS_SET_ECHO_STATE, UnsafeMutableRawPointer(s))
        }
    }

    deinit {
        if let s = state { speex_echo_state_destroy(s) }
        if let p = preprocess { speex_preprocess_state_destroy(p) }
    }

    /// near.count and far.count must equal frameSize. Returns the cleaned near-end.
    func process(near: [Int16], far: [Int16]) -> [Int16] {
        guard near.count == frameSize, far.count == frameSize else { return near }
        var out = [Int16](repeating: 0, count: frameSize)
        near.withUnsafeBufferPointer { n in
            far.withUnsafeBufferPointer { f in
                out.withUnsafeMutableBufferPointer { o in
                    speex_echo_cancellation(state, n.baseAddress, f.baseAddress, o.baseAddress)
                }
            }
        }
        out.withUnsafeMutableBufferPointer { o in
            _ = speex_preprocess_run(preprocess, o.baseAddress)
        }
        return out
    }
}
