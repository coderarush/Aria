import Foundation

/// What must be true AFTER a step for it to count as actually done — so the engine
/// verifies effects, not just "the call didn't throw". Kept simple + checkable
/// against the step's textual result; richer (AX-state) checks can plug in later.
enum PostCondition: Sendable, Equatable, Codable {
    case none                    // no explicit check (default — back-compat)
    case succeeded               // the step's tool reported ok
    case resultContains(String)  // the result text contains a marker (and ok)

    func isSatisfied(byResult result: String, ok: Bool) -> Bool {
        switch self {
        case .none: return true
        case .succeeded: return ok
        case .resultContains(let s): return ok && result.lowercased().contains(s.lowercased())
        }
    }
}
