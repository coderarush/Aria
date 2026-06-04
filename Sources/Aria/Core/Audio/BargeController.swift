import Foundation

/// Detects the user talking OVER Aria. Runs on the cleaned near-end (Aria's voice
/// already removed by the AEC), so sustained energy = the user. Only active while
/// Aria is speaking; fires `onBarge` once per onset.
final class BargeController {
    private var onsetFrames: Int
    private var energyThreshold: Double
    private var consecutive = 0
    private var playing = false
    private var fired = false
    var onBarge: (() -> Void)?

    init(onsetFrames: Int = 4, energyThreshold: Double = 600) {
        self.onsetFrames = onsetFrames
        self.energyThreshold = energyThreshold
    }

    /// Live-tune from the sensitivity slider (0…1, higher = easier to barge in).
    func configure(onsetFrames: Int, energyThreshold: Double) {
        self.onsetFrames = max(1, onsetFrames)
        self.energyThreshold = max(1, energyThreshold)
    }

    func setPlaying(_ v: Bool) {
        playing = v
        consecutive = 0
        if !v { fired = false }
    }

    func feed(_ frame: [Int16]) {
        guard playing, !fired else { return }
        let rms = sqrt(frame.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(frame.count, 1)))
        if rms >= energyThreshold {
            consecutive += 1
            if consecutive >= onsetFrames {
                fired = true
                onBarge?()
            }
        } else {
            consecutive = 0
        }
    }
}
