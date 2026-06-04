import Foundation

/// Detects the user talking OVER Aria. Runs on the cleaned near-end (Aria's voice
/// already removed by the AEC), so sustained energy = the user. Only active while
/// Aria is speaking; fires `onBarge` once per onset.
final class BargeController {
    // `feed` runs on the audio thread; `setPlaying`/`configure` on the main thread.
    // A lock guards the shared state (mirrors WakeWordEngine's feedLock pattern).
    private let lock = NSLock()
    private var onsetFrames: Int
    private var energyThreshold: Double
    private var consecutive = 0
    private var playing = false
    private var fired = false
    /// Set once before audio starts (main); read after unlock — no race.
    var onBarge: (() -> Void)?

    init(onsetFrames: Int = 4, energyThreshold: Double = 600) {
        self.onsetFrames = onsetFrames
        self.energyThreshold = energyThreshold
    }

    /// Live-tune from the sensitivity slider (0…1, higher = easier to barge in).
    func configure(onsetFrames: Int, energyThreshold: Double) {
        lock.lock(); defer { lock.unlock() }
        self.onsetFrames = max(1, onsetFrames)
        self.energyThreshold = max(1, energyThreshold)
    }

    func setPlaying(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        playing = v
        consecutive = 0
        if !v { fired = false }
    }

    func feed(_ frame: [Int16]) {
        let rms = sqrt(frame.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(frame.count, 1)))
        var shouldFire = false
        lock.lock()
        if playing, !fired {
            if rms >= energyThreshold {
                consecutive += 1
                if consecutive >= onsetFrames { fired = true; shouldFire = true }
            } else {
                consecutive = 0
            }
        }
        lock.unlock()
        if shouldFire { onBarge?() }   // call outside the lock
    }
}
