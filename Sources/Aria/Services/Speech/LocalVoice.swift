import Foundation
import AVFoundation

/// Picks the most natural installed Apple voice for the offline/quota-exhausted
/// path, so "Gemini ran out" never means "suddenly robotic". macOS ships
/// premium/enhanced neural voices (Ava, Zoe, Evan…) — most users just never
/// have them selected. Ranking is pure/testable; AVFoundation touches live at
/// the edges.
enum LocalVoice {
    static let key = "app.localVoiceID"

    /// A voice candidate reduced to what ranking needs.
    struct Candidate: Equatable {
        let id: String
        let language: String
        /// 0 default, 1 enhanced, 2 premium, 3 personal (user's own trained voice).
        let quality: Int
        let name: String
    }

    /// Rank candidates: personal > premium > enhanced > default; en-US ahead of
    /// other English; stable by name for determinism.
    static func best(_ candidates: [Candidate]) -> Candidate? {
        candidates
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                let a = $0.language == "en-US", b = $1.language == "en-US"
                if a != b { return a }
                return $0.name < $1.name
            }
            .first
    }

    /// All installed English voices as candidates (live edge).
    static func installedCandidates() -> [Candidate] {
        AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
            guard voice.language.hasPrefix("en") else { return nil }
            let quality: Int
            switch voice.quality {
            case .premium: quality = 2
            case .enhanced: quality = 1
            default: quality = 0
            }
            // Personal Voice (macOS 14+) outranks everything — it IS the user.
            let isPersonal = voice.voiceTraits.contains(.isPersonalVoice)
            return Candidate(id: voice.identifier,
                             language: voice.language,
                             quality: isPersonal ? 3 : quality,
                             name: voice.name)
        }
    }

    /// The voice the engine should use: the user's explicit pick when it's
    /// still installed, otherwise the best installed candidate, otherwise the
    /// system en-US default.
    static func resolve(preferredID: String? = UserDefaults.standard.string(forKey: key))
        -> AVSpeechSynthesisVoice? {
        if let id = preferredID, !id.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        if let top = best(installedCandidates()),
           let voice = AVSpeechSynthesisVoice(identifier: top.id) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Whether the resolved voice is high-quality (skip pitch tricks on it).
    static func isNeural(_ voice: AVSpeechSynthesisVoice?) -> Bool {
        guard let voice else { return false }
        if #available(macOS 14.0, *), voice.voiceTraits.contains(.isPersonalVoice) { return true }
        return voice.quality == .premium || voice.quality == .enhanced
    }
}
