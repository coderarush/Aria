import XCTest
@testable import Aria

final class LensIntentTests: XCTestCase {
    func testExplicitCirclePhrasesOpenExplain() {
        XCTAssertEqual(LensIntent.mode(for: "let me circle something"), .explain)
        XCTAssertEqual(LensIntent.mode(for: "Start lens"), .explain)
        XCTAssertEqual(LensIntent.mode(for: "explain what I circle"), .explain)
    }

    func testDrawPhrasesOpenDraw() {
        XCTAssertEqual(LensIntent.mode(for: "draw on my screen"), .draw)
        XCTAssertEqual(LensIntent.mode(for: "annotate my screen"), .draw)
    }

    func testOrdinaryQuestionsAreNotHijacked() {
        XCTAssertNil(LensIntent.mode(for: "what is this error in my terminal"))
        XCTAssertNil(LensIntent.mode(for: "explain this code"))
        XCTAssertNil(LensIntent.mode(for: "what's the weather"))
        XCTAssertNil(LensIntent.mode(for: "circle back to the budget later"))
    }
}
