import XCTest
@testable import Aria

final class TaskNarrationTests: XCTestCase {

    func testImperativeBecomesPresentContinuous() {
        XCTAssertEqual(TaskNarration.spoken(for: "Search the web for the weather"),
                       "Searching the web for the weather.")
        XCTAssertEqual(TaskNarration.spoken(for: "Open Mail"), "Opening Mail.")
        XCTAssertEqual(TaskNarration.spoken(for: "Save the note"), "Saving the note.")
    }

    func testUnmappedVerbKeptVerbatimWithPeriod() {
        XCTAssertEqual(TaskNarration.spoken(for: "Reticulate splines"), "Reticulate splines.")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(TaskNarration.spoken(for: "   "), "")
        XCTAssertEqual(TaskNarration.spoken(for: ""), "")
    }

    func testLongSummaryTruncated() {
        let line = TaskNarration.spoken(for: "Search the web for a very long detailed query that goes on and on past sixty characters")
        XCTAssertTrue(line.hasSuffix("…"))
        XCTAssertLessThanOrEqual(line.count, 62)
    }

    func testExistingPunctuationNotDoubled() {
        XCTAssertEqual(TaskNarration.spoken(for: "Is it raining?"), "Is it raining?")
        XCTAssertEqual(TaskNarration.spoken(for: "Done!"), "Done!")
    }
}
