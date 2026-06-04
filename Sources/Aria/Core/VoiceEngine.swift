import Foundation
import AVFoundation

/// Cloud text-to-speech for Aria's spoken responses, using Gemini's natural voice
/// exclusively (no on-device/Apple voice — it cheapened the premium feel). Strips
/// markdown so the synthesizer reads clean prose, and notifies start/finish so the
/// controller can mute wake detection while Aria speaks (preventing self-trigger).
///
/// Premium policy: there is NO robotic fallback. If Gemini TTS can't produce audio
/// (offline, no key, or sustained rate-limit after paced retries), Aria stays
/// silent — the on-screen caption still conveys the reply — and fires its
/// completion callbacks so the speech queue and wake re-arm never stall.
@MainActor
final class VoiceEngine: NSObject {
    var geminiVoiceName = "Kore"
    /// Aria's TTS plays through the shared AudioBus (so the echo canceller has her
    /// exact audio as its far-end reference and can be stopped instantly on barge-in).
    weak var audioBus: AudioBus?
    private let keyProvider: () -> String? = { KeychainManager.read(account: KeychainKey.geminiAPIKey) }

    var enabled = true

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    /// Fired when a single utterance/chunk finishes (used by StreamingVoice).
    var onChunkFinished: (() -> Void)?

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
                    // No Apple fallback — stay silent, but keep the pipeline moving.
                    Log.trace("gemini TTS unavailable (\(error)); staying silent (premium: no robotic fallback)")
                    self.onFinish?()
                    self.onChunkFinished?()
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
