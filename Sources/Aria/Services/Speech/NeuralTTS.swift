import Foundation
import CryptoKit

/// A text-to-speech source that returns 24 kHz mono 16-bit little-endian PCM —
/// the exact format Aria's `AudioBus.playReference` (and its echo canceller)
/// expects. Requesting PCM directly (not MP3) lets neural TTS ride the same
/// AEC/barge-in pipeline as Gemini, so the user can talk over Aria mid-sentence
/// even on the free cloud voices — something a plain AVAudioPlayer can't do.
protocol PCMSpeechProvider: Sendable {
    /// Synthesize `text` to 24 kHz mono 16-bit LE PCM, or throw.
    func synthesizePCM(text: String) async throws -> Data
}

// MARK: - Edge (Microsoft neural voices — free, no API key, effectively unlimited)

/// Speaks through Microsoft's Edge "read aloud" neural voices over a WebSocket.
/// Free, keyless, and not metered like Gemini — this is Aria's answer to voice
/// quotas: natural neural speech with no limit to hit.
struct EdgeTTS: PCMSpeechProvider {
    let voice: String

    static let defaultVoice = "en-US-AndrewMultilingualNeural"

    /// A curated set of the most natural en-US Edge neural voices (there are
    /// hundreds; these are the ones worth offering in a picker).
    static let voices: [(id: String, label: String)] = [
        ("en-US-AndrewMultilingualNeural", "Andrew — warm, natural (default)"),
        ("en-US-AvaMultilingualNeural", "Ava — bright, friendly"),
        ("en-US-EmmaMultilingualNeural", "Emma — calm, clear"),
        ("en-US-BrianMultilingualNeural", "Brian — easygoing"),
        ("en-US-AndrewNeural", "Andrew (classic)"),
        ("en-US-AriaNeural", "Aria — expressive"),
        ("en-US-GuyNeural", "Guy — steady"),
        ("en-US-JennyNeural", "Jenny — soft"),
        ("en-GB-RyanNeural", "Ryan — British"),
        ("en-GB-SoniaNeural", "Sonia — British"),
        ("en-AU-NatashaNeural", "Natasha — Australian"),
    ]

    private static let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    /// Must match a current Edge build or the handshake 403s. Bump alongside the
    /// edge-tts project's constant if Microsoft tightens validation.
    private static let gecVersion = "1-143.0.3650.75"

    func synthesizePCM(text: String) async throws -> Data {
        let connectionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let gec = Self.gecToken(now: Date())
        guard let url = URL(string:
            "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
            + "?TrustedClientToken=\(Self.trustedToken)"
            + "&Sec-MS-GEC=\(gec)&Sec-MS-GEC-Version=\(Self.gecVersion)&ConnectionId=\(connectionID)")
        else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
                         forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
            forHTTPHeaderField: "User-Agent")

        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        // Ask for raw PCM (not MP3) so it feeds the AudioBus at 24 kHz with no decode.
        let config = "X-Timestamp:\(Date())\r\nContent-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"riff-24khz-16bit-mono-pcm"}}}}"#
        try await socket.send(.string(config))

        let ssml = Self.ssml(text: text, voice: voice)
        try await socket.send(.string(
            "X-RequestId:\(connectionID)\r\nContent-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(Date())\r\nPath:ssml\r\n\r\n\(ssml)"))

        var riff = Data()
        receiving: while true {
            try Task.checkCancellation()
            switch try await socket.receive() {
            case .string(let message):
                if message.contains("Path:turn.end") { break receiving }
            case .data(let chunk):
                // Binary frame: [2-byte BE header length][header][audio bytes].
                guard chunk.count > 2 else { continue }
                let headerLength = Int(chunk[chunk.startIndex]) << 8
                    | Int(chunk[chunk.startIndex + 1])
                guard chunk.count > 2 + headerLength else { continue }
                let headerRange = (chunk.startIndex + 2)..<(chunk.startIndex + 2 + headerLength)
                let header = String(data: chunk.subdata(in: headerRange), encoding: .utf8) ?? ""
                if header.contains("Path:audio") {
                    riff.append(chunk.subdata(in: (chunk.startIndex + 2 + headerLength)..<chunk.endIndex))
                }
            @unknown default:
                break
            }
        }
        guard !riff.isEmpty else { throw URLError(.cannotParseResponse) }
        // The concatenated audio payloads form a RIFF/WAV stream; hand back its PCM.
        return AudioWAV.pcmData(fromWAV: riff) ?? riff
    }

    /// Sec-MS-GEC: SHA256 of Windows file-time ticks (floored to a 5-minute
    /// window) concatenated with the trusted token, uppercase hex. Pure +
    /// deterministic for a given 5-minute window so it's testable.
    static func gecToken(now: Date) -> String {
        var ticks = UInt64((now.timeIntervalSince1970 + 11_644_473_600) * 10_000_000)
        ticks -= ticks % 3_000_000_000   // floor to 300s (10M ticks/s × 300)
        let digest = SHA256.hash(data: Data("\(ticks)\(trustedToken)".utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// XML-escaped SSML for one voice line.
    static func ssml(text: String, voice: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voice)'>\(escaped)</voice></speak>"
    }
}

// MARK: - ElevenLabs (premium neural voices — optional key)

/// Best-in-class neural voices via ElevenLabs. Requests raw 24 kHz PCM so it,
/// too, rides Aria's AEC/barge-in bus. Optional — needs a (free-tier) key.
struct ElevenLabsTTS: PCMSpeechProvider {
    let apiKey: String
    let voiceID: String
    let modelID: String

    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"   // Rachel
    static let defaultModel = "eleven_turbo_v2_5"

    static let voices: [(id: String, label: String)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel — calm (default)"),
        ("EXAVITQu4vr4xnSDxMaL", "Sarah — soft"),
        ("pNInz6obpgDQGcFmaJgB", "Adam — deep"),
        ("ErXwobaYiN019PkySvjV", "Antoni — warm"),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh — young"),
        ("VR6AewLTigWG4xSOukaG", "Arnold — crisp"),
    ]

    init(apiKey: String, voiceID: String = defaultVoiceID, modelID: String = defaultModel) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.modelID = modelID
    }

    func synthesizePCM(text: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw NSError(domain: "AriaTTS.eleven", code: 401) }
        // pcm_24000 → raw 24 kHz 16-bit mono PCM, no container to strip.
        guard let url = URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=pcm_24000")
        else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw NSError(domain: "AriaTTS.eleven", code: status) }
        guard !data.isEmpty else { throw URLError(.cannotParseResponse) }
        return data
    }
}

// MARK: - WAV parsing

enum AudioWAV {
    /// Extract the PCM payload from a RIFF/WAV stream by walking its chunks to
    /// the `data` subchunk. Tolerant of extra chunks (fmt/LIST/fact) before it;
    /// returns nil if the stream isn't a WAV we recognize.
    static func pcmData(fromWAV wav: Data) -> Data? {
        let bytes = [UInt8](wav)
        guard bytes.count > 12,
              bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46, // "RIFF"
              bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45 // "WAVE"
        else { return nil }

        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
                | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            let dataStart = offset + 8
            if id == "data" {
                let end = min(dataStart + size, bytes.count)
                guard dataStart <= end else { return nil }
                return Data(bytes[dataStart..<end])
            }
            // Chunks are word-aligned: skip the payload plus any pad byte.
            offset = dataStart + size + (size & 1)
        }
        return nil
    }
}
