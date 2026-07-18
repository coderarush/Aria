import Foundation

/// The intent behind a sound — used to decide when a cue is appropriate.
enum SoundCategory: String, Sendable, CaseIterable {
    case interaction, thinking, success, warning, completion
}

/// SoundProfile (Phase 9 audio): the source of truth for what each cue *means*
/// and whether it should play. It classifies the existing `UISounds.Kind` cues
/// into categories and applies one policy — subtle, silent-mode aware: in silent
/// mode only warnings still inform. No new audio assets, no persistence; it sits
/// on top of the synthesized UISounds already in place.
enum SoundProfile {

    static func category(for kind: UISounds.Kind) -> SoundCategory {
        switch kind {
        case .wake, .tick, .dismiss, .notification: return .interaction
        case .thinking, .task:                       return .thinking
        case .confirm:                               return .success
        case .done:                                  return .completion
        case .error:                                 return .warning
        }
    }

    /// Whether a cue should play. Silent mode suppresses everything except
    /// warnings, which still need to inform the user.
    static func shouldPlay(_ kind: UISounds.Kind, silentMode: Bool) -> Bool {
        guard silentMode else { return true }
        return category(for: kind) == .warning
    }
}
