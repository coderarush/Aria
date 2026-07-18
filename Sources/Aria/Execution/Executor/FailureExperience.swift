import Foundation

/// How a failure is surfaced (spec §116).
struct FailureResponse: Sendable {
    let explanation: String
    let recoverable: Bool
    let nextStep: String
    let blamesUser: Bool
}

/// Turns a failure into something the user can act on (spec §116): explain,
/// recover, continue. Never blames the user, hides state, or restarts silently.
struct FailureExperience: Sendable {

    func handle(error: String, recoverable: Bool) -> FailureResponse {
        FailureResponse(
            explanation: "Couldn't complete that — \(error).",
            recoverable: recoverable,
            nextStep: recoverable ? "I can retry or adjust the approach — your call."
                                  : "Paused here so nothing is lost — tell me how to proceed.",
            blamesUser: false)
    }
}
