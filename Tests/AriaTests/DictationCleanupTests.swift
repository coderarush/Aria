import XCTest
@testable import Aria

final class DictationCleanupTests: XCTestCase {
    func testTrimsAndCapitalizesAndPunctuates() {
        XCTAssertEqual(DictationController.cleanup("  hello there  "), "Hello there.")
    }

    func testCollapsesRunawayWhitespace() {
        XCTAssertEqual(DictationController.cleanup("send  the\n\nreport"), "Send the report.")
    }

    func testStripsStandaloneFillers() {
        XCTAssertEqual(DictationController.cleanup("um can you uh check this"), "Can you check this.")
    }

    func testKeepsExistingTerminalPunctuation() {
        XCTAssertEqual(DictationController.cleanup("is it ready?"), "Is it ready?")
        XCTAssertEqual(DictationController.cleanup("stop!"), "Stop!")
    }

    func testDoesNotRewriteRealWords() {
        // "like" and "so" are NOT treated as fillers — removing them changes meaning.
        XCTAssertEqual(DictationController.cleanup("I like it so much"), "I like it so much.")
    }

    func testEmptyAndFillerOnlyReturnEmpty() {
        XCTAssertEqual(DictationController.cleanup("   "), "")
        XCTAssertEqual(DictationController.cleanup("um uh hmm"), "")
    }
}
