import Foundation

/// The writing register Aria uses when drafting messages and emails.
/// `.auto` means Aria picks the tone from context (default). All other cases
/// inject an explicit instruction into the drafting prompt.
enum WritingTone: String, CaseIterable, Codable, Sendable {
    case auto, formal, casual, brief, friendly, professional

    /// Instruction prepended to drafting prompts. Empty for `.auto`.
    var instruction: String {
        switch self {
        case .auto:         return ""
        case .formal:       return "Write formally and professionally. Use complete sentences, avoid contractions."
        case .casual:       return "Write in a casual, friendly tone. Contractions are fine. Keep it conversational."
        case .brief:        return "Be extremely concise. Get to the point immediately. Bullet points if helpful."
        case .friendly:     return "Be warm and friendly. Use a positive tone. Make the reader feel valued."
        case .professional: return "Write professionally but approachably. Clear, confident, and respectful."
        }
    }
}

/// Manages the active writing tone for all Aria drafts. Thread-safe actor.
/// Inject `ToneManager()` in tests (fresh instance); use `.shared` in production.
actor ToneManager {
    static let shared = ToneManager()

    private(set) var current: WritingTone = .auto

    /// Update the active tone.
    func set(_ tone: WritingTone) async {
        current = tone
    }

    /// Reset to the default auto tone.
    func reset() async {
        current = .auto
    }

    /// Returns the instruction string for the current tone.
    /// Empty when `.auto` so non-toned prompts are byte-identical.
    func toneInstruction() async -> String {
        current.instruction
    }
}
