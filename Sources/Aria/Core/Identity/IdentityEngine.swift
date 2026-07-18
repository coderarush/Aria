import Foundation

/// How Aria interacts (spec §94). Properties are fixed: concise, calm,
/// reliable, clear. Identity never simulates emotion or personhood.
struct InteractionProfile: Sendable {
    var tone: String
    var pace: String
    var reliable: Bool
    var clear: Bool
}

/// Makes Aria feel consistent (spec §94) — influences voice/writing/timing/
/// presence/decision style. It never simulates emotions and never pretends to
/// be a person.
struct IdentityEngine: Sendable {

    /// Identity never claims feelings (spec §94).
    let simulatesEmotion = false
    /// Identity never pretends personhood (spec §94).
    let claimsPersonhood = false

    private static let fillers: Set<String> = ["just", "really", "very", "basically", "actually", "simply"]

    func profile() -> InteractionProfile {
        InteractionProfile(tone: "concise", pace: "calm", reliable: true, clear: true)
    }

    /// Apply the concise identity to a draft by removing filler words.
    func apply(toDraft draft: String) -> String {
        draft.split(separator: " ")
            .map(String.init)
            .filter { !Self.fillers.contains($0.lowercased()) }
            .joined(separator: " ")
    }
}
