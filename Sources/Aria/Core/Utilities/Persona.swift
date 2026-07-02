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

/// Free-form standing instructions the user writes once and Aria honors in
/// every conversation ("always answer in metric", "call me Cap", "no emoji").
/// Read straight from UserDefaults so prompt assembly (actors, any thread)
/// never needs a MainActor hop — same pattern as `PersonaStyle`.
enum CustomInstructions {
    static let key = "app.customInstructions"
    /// Generous but bounded — the prompt budget is shared with tools + context.
    static let maxLength = 1200

    static var current: String {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength))
    }

    /// Appended to every system prompt after the persona style. Empty when unset.
    static var promptSuffix: String {
        let text = current
        guard !text.isEmpty else { return "" }
        return "\nThe user's standing instructions (always honor these): \(text)"
    }
}
