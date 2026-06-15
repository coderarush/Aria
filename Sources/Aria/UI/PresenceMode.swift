import SwiftUI

/// How Aria is physically present on screen. A pure projection of the island
/// state machine so the wake/consolidate/splash choreography can be unit-tested
/// without rendering anything.
///
/// - `.hidden`  nothing drawn, no animation ticking (idle = zero work)
/// - `.border`  faint blob-like glow rotating around the screen perimeter
/// - `.blob`    the consolidated droplet at the user's saved anchor
enum PresenceMode: Equatable {
    case hidden, border, blob

    static func from(state: IslandViewModel.State, visible: Bool, hasSuggestion: Bool) -> PresenceMode {
        guard visible || hasSuggestion else { return .hidden }
        switch state {
        case .idle:       return hasSuggestion ? .blob : .hidden
        case .listening:  return .border
        case .thinking:   return .blob
        case .executing:  return .border
        case .responding: return .blob
        case .error:      return .blob
        }
    }
}
