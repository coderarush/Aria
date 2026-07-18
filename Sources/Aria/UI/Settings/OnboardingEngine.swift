import Foundation

/// The first-run flow (spec §117), targeting time-to-value under 3 minutes.
actor OnboardingEngine {

    enum Step: String, Sendable, CaseIterable {
        case welcome, permission, firstObjective, firstSuccess, continuation
    }

    private(set) var step: Step = .welcome
    private(set) var done = false

    /// Estimated time-to-value in seconds (spec §117 goal: < 3 minutes).
    static let estimatedSeconds = 150

    func advance() {
        guard let index = Step.allCases.firstIndex(of: step) else { return }
        if index + 1 < Step.allCases.count {
            step = Step.allCases[index + 1]
        } else {
            done = true
        }
    }

    func isComplete() -> Bool { done }
}
