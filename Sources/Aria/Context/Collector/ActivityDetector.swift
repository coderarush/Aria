import Foundation

/// Richer activity modes (spec §76 Attention V2). Modes influence presence,
/// suggestions, and surface updates — never execution.
enum ActivityMode: String, Sendable, CaseIterable {
    case working, thinking, meeting, moving, idle, flow
}

/// Derives the current activity mode from fused understanding (spec §76).
/// Extends the Part 2 attention model with multimodal signals.
struct ActivityDetector: Sendable {

    func detect(screen: ScreenUnderstanding?,
                audio: AudioUnderstanding?,
                idleSeconds: TimeInterval,
                focusSeconds: TimeInterval) -> ActivityMode {
        if idleSeconds >= 120 { return .idle }
        if let audio, audio.speaking, audio.speakerCount >= 2 { return .meeting }
        if let screen, screen.intent == "coding" || screen.intent == "writing" {
            return focusSeconds >= 600 ? .flow : .working
        }
        return .thinking
    }
}
