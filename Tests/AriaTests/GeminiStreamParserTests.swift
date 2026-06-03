import XCTest
@testable import Aria

final class GeminiStreamParserTests: XCTestCase {
    func testParsesTextDeltasAcrossChunkBoundaries() {
        var p = GeminiStreamParser()
        let e1 = p.consume("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hel")
        XCTAssertTrue(e1.isEmpty)
        let e2 = p.consume("lo\"}]}}]}\n\n")
        XCTAssertEqual(e2, [.text("Hello")])
    }

    func testParsesFunctionCall() {
        var p = GeminiStreamParser()
        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"open_app\",\"args\":{\"name\":\"Spotify\"}}}]}}]}\n\n"
        XCTAssertEqual(p.consume(line), [.functionCall(name: "open_app", args: ["name": "Spotify"])])
    }

    func testIgnoresDoneSentinelAndBlankLines() {
        var p = GeminiStreamParser()
        XCTAssertEqual(p.consume("\n\ndata: [DONE]\n\n"), [])
    }
}
