import Foundation

/// The reduced command vocabulary (spec §102). Aria explains its reasoning
/// internally, not externally.
enum Command: String, Sendable {
    case continueWork, handleThis, remember, finish, status, prepare, pause, resume, unknown
}

/// Maps natural phrasing to a small command set and separates terse external
/// responses from richer internal reasoning (spec §102).
struct CommandModel: Sendable {

    func parse(_ input: String) -> Command {
        let text = input.lowercased()
        if text.contains("handle") { return .handleThis }
        if text.contains("continue") || text.contains("pick up") || text.contains("pick back up") { return .continueWork }
        if text.contains("remember") { return .remember }
        if text.contains("finish") { return .finish }
        if text.contains("status") { return .status }
        if text.contains("prepare") { return .prepare }
        if text.contains("pause") { return .pause }
        if text.contains("resume") { return .resume }
        return .unknown
    }

    /// Short, user-facing acknowledgement.
    func externalResponse(for command: Command) -> String {
        switch command {
        case .continueWork: return "Continuing."
        case .handleThis: return "On it."
        case .remember: return "Noted."
        case .finish: return "Finishing up."
        case .status: return "Here's where things stand."
        case .prepare: return "Preparing."
        case .pause: return "Paused."
        case .resume: return "Resuming."
        case .unknown: return "Didn't catch that."
        }
    }

    /// Internal-only reasoning (never surfaced to the user).
    func internalExplanation(for command: Command) -> String {
        "command=\(command.rawValue); resolving objective + context, then dispatching the matching runtime action under current authority"
    }
}
