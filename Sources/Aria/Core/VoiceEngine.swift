import AppKit
import AVFoundation

/// On-device and cloud text-to-speech for Aria's spoken responses. Strips markdown so the
/// synthesizer reads clean prose, and notifies start/finish so the controller
/// can mute wake detection while Aria speaks (preventing self-triggering).
@MainActor
final class VoiceEngine: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()

    enum Kind: String { case apple, gemini }
    var kind: Kind = .apple
    var geminiVoiceName = "Kore"
    private var audioPlayer: AVAudioPlayer?
    private let keyProvider: () -> String? = { KeychainManager.read(account: KeychainKey.geminiAPIKey) }

    var enabled = true
    var voiceIdentifier: String?
    var rate: Float = 0.46 * (AVSpeechUtteranceMaximumSpeechRate + AVSpeechUtteranceMinimumSpeechRate)

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    /// Fired when a single utterance/chunk finishes (used by StreamingVoice).
    var onChunkFinished: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ message: String) {
        guard enabled else { return }
        let clean = Self.spokenText(from: message)
        guard !clean.isEmpty else { return }
        onStart?()
        if kind == .gemini {
            speakWithGemini(clean)
        } else {
            speakWithApple(clean)
        }
    }

    private func speakWithApple(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) { u.voice = v }
        else { u.voice = Self.preferredVoice() }
        u.rate = rate
        synth.speak(u)
    }

    private func speakWithGemini(_ text: String) {
        Task { [weak self] in
            guard let self else { return }
            let key = self.keyProvider() ?? ""
            // Give Gemini one paced retry on a momentary 429 before dropping to the
            // Apple voice — under normal use this keeps the natural voice instead of
            // flipping to robotic on a transient rate-limit.
            for attempt in 0..<2 {
                do {
                    let wav = try await Self.synthesizeGemini(text: text, voice: self.geminiVoiceName, apiKey: key)
                    try self.play(wav)        // onFinish fires from AVAudioPlayer delegate
                    return
                } catch {
                    let is429 = (error as NSError).code == 429
                    if is429, attempt == 0 {
                        Log.trace("gemini TTS 429 — pacing then retrying once")
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        continue
                    }
                    Log.trace("gemini TTS failed (\(error)); falling back to Apple voice")
                    self.speakWithApple(text) // onFinish fires from speech delegate
                    return
                }
            }
        }
    }

    private func play(_ wav: Data) throws {
        let player = try AVAudioPlayer(data: wav)
        player.delegate = self
        self.audioPlayer = player
        player.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish?(); self.onChunkFinished?() }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        synth.stopSpeaking(at: .immediate)
    }

    /// Prefer an enhanced/premium en-US voice; fall back to the default en-US.
    nonisolated static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let enUS = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        if let enhanced = enUS.first(where: { $0.quality == .premium })
            ?? enUS.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// True if a natural (Premium/Enhanced) English voice is installed.
    nonisolated static func hasNaturalVoiceInstalled() -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains {
            $0.language.hasPrefix("en") && ($0.quality == .premium || $0.quality == .enhanced)
        }
    }

    /// Identifier of the best available voice (Premium/Enhanced preferred).
    nonisolated static func bestVoiceIdentifier() -> String? { preferredVoice()?.identifier }

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
        Task { @MainActor in self.onFinish?(); self.onChunkFinished?() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.onChunkFinished?() }
    }

    /// Speak a single chunk (no onStart). Routes completion to onChunkFinished.
    func speakChunk(_ text: String) {
        let clean = Self.spokenText(from: text)
        guard !clean.isEmpty else { Task { @MainActor in self.onChunkFinished?() }; return }
        if kind == .gemini { speakWithGemini(clean) } else { speakWithApple(clean) }
    }

    /// Gemini TTS → WAV bytes (24kHz mono 16-bit PCM wrapped in a WAV header).
    static func synthesizeGemini(text: String, voice: String, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw NSError(domain: "AriaTTS", code: 401) }
        let model = "gemini-2.5-flash-preview-tts"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let payload: [String: Any] = [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]]
            ]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw NSError(domain: "AriaTTS", code: status) }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands = root["candidates"] as? [[String: Any]],
            let content = cands.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let inline = parts.first(where: { $0["inlineData"] != nil })?["inlineData"] as? [String: Any],
            let b64 = inline["data"] as? String,
            let pcm = Data(base64Encoded: b64)
        else { throw NSError(domain: "AriaTTS", code: -1) }
        return wavData(fromPCM: pcm)
    }

    /// Wrap raw little-endian 16-bit mono PCM in a minimal WAV container.
    static func wavData(fromPCM pcm: Data, sampleRate: Int = 24000, channels: Int = 1, bits: Int = 16) -> Data {
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        var h = Data()
        func str(_ s: String) { h.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bits))
        str("data"); u32(UInt32(pcm.count))
        return h + pcm
    }
}
