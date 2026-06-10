import XCTest
@testable import Aria

final class VoiceEngineTests: XCTestCase {
    func testStripsMarkdownAndUrls() {
        let input = "Opening **Spotify** for you.\n\n**open_app** → Opened https://open.spotify.com"
        let out = VoiceEngine.spokenText(from: input)
        XCTAssertFalse(out.contains("*"))
        XCTAssertFalse(out.contains("→"))
        XCTAssertFalse(out.contains("http"))
        XCTAssertTrue(out.contains("Opening Spotify for you"))
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(VoiceEngine.spokenText(from: "Done.\n\n\nNext."), "Done. Next.")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(VoiceEngine.spokenText(from: "   \n  "), "")
    }

    @MainActor
    func testWavDataWrapsPCMInValidHeader() {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let wav = VoiceEngine.wavData(fromPCM: pcm, sampleRate: 24000, channels: 1, bits: 16)

        XCTAssertEqual(wav.count, pcm.count + 44)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(Array(wav.suffix(pcm.count)), Array(pcm))
    }
}
