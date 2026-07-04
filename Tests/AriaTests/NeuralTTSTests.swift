import XCTest
@testable import Aria

final class EdgeTTSTests: XCTestCase {

    func testGECTokenIsStableWithinFiveMinuteWindow() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)   // fixed instant
        let a = EdgeTTS.gecToken(now: base)
        let b = EdgeTTS.gecToken(now: base.addingTimeInterval(120))   // same 5-min window
        XCTAssertEqual(a, b, "token must be stable inside a 5-minute window")
        XCTAssertEqual(a.count, 64, "SHA256 hex is 64 chars")
        XCTAssertEqual(a, a.uppercased(), "token must be uppercase hex")
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }

    func testGECTokenRotatesAcrossWindows() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = EdgeTTS.gecToken(now: base)
        let c = EdgeTTS.gecToken(now: base.addingTimeInterval(400))   // next 5-min window
        XCTAssertNotEqual(a, c, "token must change across 5-minute windows")
    }

    func testSSMLEscapesMarkup() {
        let ssml = EdgeTTS.ssml(text: "Tom & <Jerry> say \"hi\"", voice: "en-US-AndrewNeural")
        XCTAssertTrue(ssml.contains("Tom &amp; &lt;Jerry&gt;"))
        XCTAssertTrue(ssml.contains("name='en-US-AndrewNeural'"))
        XCTAssertFalse(ssml.contains("<Jerry>"), "raw angle brackets would break the XML")
    }

    func testVoiceCatalogNonEmptyAndDefaultPresent() {
        XCTAssertFalse(EdgeTTS.voices.isEmpty)
        XCTAssertTrue(EdgeTTS.voices.contains { $0.id == EdgeTTS.defaultVoice })
    }
}

final class AudioWAVTests: XCTestCase {

    func testExtractsPCMFromWellFormedWAV() {
        let pcm = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let wav = VoiceEngine.wavData(fromPCM: pcm, sampleRate: 24000)
        let extracted = AudioWAV.pcmData(fromWAV: wav)
        XCTAssertEqual(extracted, pcm)
    }

    func testToleratesChunkBeforeData() {
        // RIFF + WAVE, then a LIST chunk (odd size → padded), then data.
        var wav = Data()
        func ascii(_ s: String) { wav.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        let pcm = Data([0xAA, 0xBB, 0xCC, 0xDD])
        ascii("RIFF"); u32(0); ascii("WAVE")
        ascii("LIST"); u32(3); wav.append(contentsOf: [0x49, 0x4E, 0x46]); wav.append(0x00) // 3 bytes + pad
        ascii("data"); u32(UInt32(pcm.count)); wav.append(pcm)
        XCTAssertEqual(AudioWAV.pcmData(fromWAV: wav), pcm)
    }

    func testRejectsNonWAV() {
        XCTAssertNil(AudioWAV.pcmData(fromWAV: Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(AudioWAV.pcmData(fromWAV: Data("not a wav at all".utf8)))
    }
}

final class ElevenLabsTTSTests: XCTestCase {

    func testMissingKeyThrows() async {
        let provider = ElevenLabsTTS(apiKey: "")
        do {
            _ = try await provider.synthesizePCM(text: "hello")
            XCTFail("empty key must throw before any network call")
        } catch {
            XCTAssertEqual((error as NSError).code, 401)
        }
    }

    func testVoiceCatalogHasDefault() {
        XCTAssertTrue(ElevenLabsTTS.voices.contains { $0.id == ElevenLabsTTS.defaultVoiceID })
    }
}

final class TTSEngineTests: XCTestCase {

    func testEngineRawValuesRoundTrip() {
        for engine in VoiceEngine.TTSEngine.allCases {
            XCTAssertEqual(VoiceEngine.TTSEngine(rawValue: engine.rawValue), engine)
            XCTAssertFalse(engine.label.isEmpty)
        }
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(VoiceEngine.TTSEngine(rawValue: "whisper"))
    }

    func testDefaultEngineIsEdge() {
        // The free, keyless, unlimited engine is the shipped default.
        XCTAssertEqual(VoiceEngine.TTSEngine.allCases.first, .edge)
    }
}
