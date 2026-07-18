import Foundation

/// Frame-by-frame voice-activity detection over RMS levels. Reports speaking
/// state (with onset debounce + silence hangover) and a one-shot endpoint flag.
struct VoiceActivity {
    let threshold: Float
    let onsetFrames: Int
    let hangoverFrames: Int

    private var aboveCount = 0
    private var silentCount = 0
    private(set) var isSpeaking = false

    struct Result { var isSpeaking: Bool; var didEndpoint: Bool; var didOnset: Bool }

    init(threshold: Float = 0.08, onsetFrames: Int = 3, hangoverFrames: Int = 8) {
        self.threshold = threshold; self.onsetFrames = onsetFrames; self.hangoverFrames = hangoverFrames
    }

    mutating func process(_ rms: Float) -> Result {
        var didOnset = false, didEndpoint = false
        if rms >= threshold {
            aboveCount += 1; silentCount = 0
            if !isSpeaking && aboveCount >= onsetFrames { isSpeaking = true; didOnset = true }
        } else {
            silentCount += 1; aboveCount = 0
            if isSpeaking && silentCount >= hangoverFrames { isSpeaking = false; didEndpoint = true }
        }
        return Result(isSpeaking: isSpeaking, didEndpoint: didEndpoint, didOnset: didOnset)
    }
}
