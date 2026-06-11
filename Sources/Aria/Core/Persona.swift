import Foundation

/// User-selectable personality flavor, layered on top of Aria's base persona.
/// Read straight from UserDefaults so prompt assembly (actors, any thread)
/// never needs a MainActor hop.
enum PersonaStyle: String, CaseIterable {
    case balanced   // the shipped default voice
    case warm       // softer, more encouraging
    case witty      // a little more playful
    case concise    // minimum words, maximum signal

    static let key = "app.personaStyle"

    static var current: PersonaStyle {
        PersonaStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .balanced
    }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .warm:     return "Warm"
        case .witty:    return "Witty"
        case .concise:  return "Concise"
        }
    }

    /// Appended to every system prompt (chat + fallback providers).
    var promptSuffix: String {
        switch self {
        case .balanced: return ""
        case .warm:
            return "\nStyle: be especially warm and encouraging — a kind friend who's great at their job."
        case .witty:
            return "\nStyle: dry wit welcome — a clever aside now and then, never at the user's expense."
        case .concise:
            return "\nStyle: be maximally brief. One short sentence whenever it suffices. No pleasantries."
        }
    }
}
