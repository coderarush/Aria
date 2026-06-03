import XCTest
@testable import Aria

final class SentenceChunkerTests: XCTestCase {
    func testEmitsCompleteSentencesAndKeepsRemainder() {
        var chunker = SentenceChunker()
        XCTAssertEqual(chunker.push("Hello there."), ["Hello there."])
        XCTAssertEqual(chunker.push(" How are"), [])          // incomplete
        XCTAssertEqual(chunker.push(" you? Good"), ["How are you?"])
        XCTAssertEqual(chunker.flush(), "Good")               // trailing remainder
    }

    func testSplitsOnQuestionAndExclamation() {
        var chunker = SentenceChunker()
        XCTAssertEqual(chunker.push("Done! Next?"), ["Done!", "Next?"])
    }

    func testLengthCapForciblyEmits() {
        var chunker = SentenceChunker(maxChunk: 10)
        // No sentence end, but exceeds cap → emit what we have at a word boundary.
        XCTAssertEqual(chunker.push("aaa bbb ccc ddd"), ["aaa bbb"])
    }
}
