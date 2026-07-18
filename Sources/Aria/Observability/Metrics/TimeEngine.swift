import Foundation

/// Estimates time saved (spec §113): minutes saved and context switches
/// avoided. Surfaced only when the total is meaningful.
actor TimeEngine {

    private var minutesSaved: Double = 0
    private var switchesAvoided: Int = 0
    private let meaningfulThreshold: Double

    init(meaningfulThreshold: Double = 5) {
        self.meaningfulThreshold = meaningfulThreshold
    }

    func record(minutesSaved: Double, switchesAvoided: Int) {
        self.minutesSaved += minutesSaved
        self.switchesAvoided += switchesAvoided
    }

    func totalMinutesSaved() -> Double { minutesSaved }

    func isMeaningful() -> Bool { minutesSaved >= meaningfulThreshold }

    /// A user-facing summary, or nil when not worth showing (spec §113).
    func summary() -> String? {
        guard isMeaningful() else { return nil }
        return "Saved ~\(Int(minutesSaved)) min, avoided \(switchesAvoided) context switches"
    }
}
