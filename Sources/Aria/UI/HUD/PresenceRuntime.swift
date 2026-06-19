import Foundation

/// Aria's lifecycle state — what she is actually doing right now. Derived from
/// real engine signals only; never fabricated.
enum PresenceState: String, Sendable, CaseIterable {
    case idle, aware, thinking, planning, acting, waiting, complete

    /// Anything but idle means Aria is present and should be shown.
    var isActive: Bool { self != .idle }

    var label: String {
        switch self {
        case .idle:     return "idle"
        case .aware:    return "aware"
        case .thinking: return "thinking"
        case .planning: return "planning"
        case .acting:   return "acting"
        case .waiting:  return "waiting"
        case .complete: return "done"
        }
    }
}

/// PresenceRuntime (Phase 8): maps Aria's REAL state to her lifecycle and to the
/// always-blob presence. It owns no animation (the PresenceChoreographer drives
/// the subtle transitions) and invents nothing — every PresenceState comes from a
/// genuine input (the island state machine, a pending approval, an active plan),
/// so progress is never faked.
enum PresenceRuntime {

    /// The lifecycle state from the live signals. A real pending approval is a
    /// waiting state regardless of what the island shows.
    static func state(island: IslandViewModel.State,
                      hasSuggestion: Bool = false,
                      awaitingApproval: Bool = false,
                      isPlanning: Bool = false) -> PresenceState {
        if awaitingApproval { return .waiting }
        switch island {
        case .idle:       return hasSuggestion ? .aware : .idle
        case .listening:  return .aware
        case .thinking:   return isPlanning ? .planning : .thinking
        case .executing:  return .acting
        case .responding: return .complete
        case .error:      return .waiting
        }
    }

    /// Presence mode for a lifecycle state under the always-blob contract: the
    /// blob whenever Aria is active (or explicitly visible), hidden only when
    /// idle and not surfaced.
    static func mode(for state: PresenceState, visible: Bool) -> PresenceMode {
        if state.isActive { return .blob }
        return visible ? .blob : .hidden
    }
}
