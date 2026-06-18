import SwiftUI

/// How Aria is physically present on screen.
///
/// - `.hidden`  nothing drawn, no animation ticking (idle = zero work)
/// - `.border`  (legacy, kept for choreographer compatibility — not used)
/// - `.blob`    the consolidated droplet; always shown when Aria is active
enum PresenceMode: Equatable {
    case hidden, border, blob

    static func from(state: IslandViewModel.State, visible: Bool, hasSuggestion: Bool) -> PresenceMode {
        guard visible || hasSuggestion else { return .hidden }
        return .blob   // no outer glow — always the blob when active
    }
}
