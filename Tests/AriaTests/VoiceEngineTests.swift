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
}
