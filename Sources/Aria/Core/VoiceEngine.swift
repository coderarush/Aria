import AppKit
import AVFoundation

/// On-device text-to-speech for Aria's spoken responses. Strips markdown so the
/// synthesizer reads clean prose, and notifies start/finish so the controller
/// can mute wake detection while Aria speaks (preventing self-triggering).
@MainActor
final class VoiceEngine: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    var enabled = true
    var voiceIdentifier: String?
    var rate: Float = 0.46 * (AVSpeechUtteranceMaximumSpeechRate + AVSpeechUtteranceMinimumSpeechRate)

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ message: String) {
        guard enabled else { return }
        let clean = Self.spokenText(from: message)
        guard !clean.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: clean)
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = v
        } else {
            utterance.voice = Self.preferredVoice()
        }
        utterance.rate = rate
        onStart?()
        synth.speak(utterance)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// Prefer an enhanced/premium en-US voice; fall back to the default en-US.
    nonisolated static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let enUS = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        if let enhanced = enUS.first(where: { $0.quality == .premium })
            ?? enUS.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Open System Settings where the user can download free Enhanced/Premium
    /// voices (Spoken Content). Best-effort across macOS versions.
    static func openVoiceDownloadSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Remove markdown emphasis, code ticks, arrows, and URLs; collapse whitespace.
    nonisolated static func spokenText(from message: String) -> String {
        var s = message
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for token in ["**", "*", "`", "→", "_", "#"] {
            s = s.replacingOccurrences(of: token, with: " ")
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
