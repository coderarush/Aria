import Foundation
import AVFoundation

/// Cloud text-to-speech for Aria's spoken responses. Tries Gemini's natural voice
/// first (3 attempts with 429 pacing). If Gemini is unavailable, falls back to
/// AVSpeechSynthesizer so Aria always speaks rather than going silent.
@MainActor
final class VoiceEngine: NSObject {
    var geminiVoiceName = "Kore"
    /// Aria's TTS plays through the shared AudioBus (so the echo canceller has her
    /// exact audio as its far-end reference and can be stopped instantly on barge-in).
    weak var audioBus: AudioBus?
    // The keychain item may hold several keys (one per line); TTS uses the first.
    private let keyProvider: () -> String? = {
        (KeychainManager.read(account: KeychainKey.geminiAPIKey) ?? "")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    var enabled = true

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    /// Fired when a single utterance/chunk finishes (used by StreamingVoice).
    var onChunkFinished: (() -> Void)?

    private let appleSynth = AVSpeechSynthesizer()

    /// Speak a full message (fires onStart).
    func speak(_ message: String) {
        guard enabled else { return }
        let clean = Self.spokenText(from: message)
        guard !clean.isEmpty else { return }
        onStart?()
        speakWithGemini(clean)
    }

    /// Speak a single chunk (no onStart). Completion routes to onChunkFinished.
    func speakChunk(_ text: String) {
        guard enabled else { onChunkFinished?(); return }   // respect the Settings toggle
        let clean = Self.spokenText(from: text)
        guard !clean.isEmpty else { onChunkFinished?(); return }
        speakWithGemini(clean)
    }

    private func speakWithGemini(_ text: String) {
        Task { [weak self] in
            guard let self else { return }
            let key = self.keyProvider() ?? ""
            // Up to 3 attempts, pacing on a momentary 429, so the natural voice wins
            // under normal use instead of going silent on a transient rate-limit.
            for attempt in 0..<3 {
                do {
                    let wav = try await Self.synthesizeGemini(text: text, voice: self.geminiVoiceName, apiKey: key)
                    try self.play(wav)            // onFinish/onChunkFinished fire from the player delegate
                    return
                } catch {
                    let is429 = (error as NSError).code == 429
                    if is429, attempt < 2 {
                        let wait = 1.2 + Double(attempt) * 1.3   // 1.2s, 2.5s
                        Log.trace("gemini TTS 429 — pacing \(wait)s then retry \(attempt + 1)/2")
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        continue
                    }
                    // Gemini unavailable — fall back to Apple TTS so Aria always speaks.
                    Log.trace("gemini TTS unavailable (\(error)); falling back to Apple TTS")
                    self.speakWithApple(text)
                    return
                }
            }
        }
    }

    private func play(_ wav: Data) throws {
        guard let bus = audioBus else { throw NSError(domain: "AriaTTS", code: -2) }
        // synthesizeGemini returns a WAV (44-byte header + 24 kHz mono Int16 PCM).
        let pcm = wav.count > 44 ? wav.subdata(in: 44..<wav.count) : wav
        bus.playReference(pcm: pcm, pcmRate: 24000) { [weak self] in
            Task { @MainActor in self?.onFinish?(); self?.onChunkFinished?() }
        }
    }

    func stop() {
        audioBus?.stopPlayback()
        appleSynth.stopSpeaking(at: .immediate)
    }

    private func speakWithApple(_ text: String) {
        appleSynth.delegate = self
        let utt = AVSpeechUtterance(string: text)
        utt.rate = 0.52          // slightly faster than default (0.5) — feels more natural
        // Best installed voice (personal > premium > enhanced) so the offline
        // path stays natural. Pitch tricks only help the compact default voice —
        // neural voices sound best untouched.
        let voice = LocalVoice.resolve()
        utt.voice = voice
        utt.pitchMultiplier = LocalVoice.isNeural(voice) ? 1.0 : 1.1
        appleSynth.speak(utt)
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

    /// Gemini TTS → WAV bytes (24kHz mono 16-bit PCM wrapped in a WAV header).
    static func synthesizeGemini(text: String, voice: String, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw NSError(domain: "AriaTTS", code: 401) }
        let model = "gemini-2.5-flash-preview-tts"
        guard let url = GeminiClient.geminiURL(model: model, apiKey: apiKey) else {
            throw NSError(domain: "AriaTTS", code: -3)
        }
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
    nonisolated static func wavData(fromPCM pcm: Data, sampleRate: Int = 24000, channels: Int = 1, bits: Int = 16) -> Data {
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        var h = Data()
        func str(_ s: String) { h.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bits))
        str("data"); u32(UInt32(pcm.count))
        return h + pcm
    }
}

extension VoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.onFinish?()
            self?.onChunkFinished?()
        }
    }
}
