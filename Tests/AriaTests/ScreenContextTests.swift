import XCTest
@testable import Aria

/// The AX capture in ScreenContext.snapshot() needs a live UI + Accessibility grant,
/// so these cover the pure, deterministic pieces: the cap helper and how the ambient
/// fields render into the model's SYSTEM CONTEXT block.
final class ScreenContextTests: XCTestCase {

    func testCapTrimsAndTruncates() {
        XCTAssertEqual(ScreenContext.cap("  hello  ", 100), "hello")
        XCTAssertEqual(ScreenContext.cap(String(repeating: "x", count: 10), 4), "xxxx…")
        XCTAssertEqual(ScreenContext.cap("", 10), "")
    }

    func testAmbientLinesEmptyWhenNothingKnown() {
        let c = GeminiClient.SystemContext(currentApp: "Safari", time: Date(), username: "me")
        XCTAssertEqual(c.ambientLines, "")
    }

    func testAmbientLinesRenderKnownFieldsOnly() {
        var c = GeminiClient.SystemContext(currentApp: "Safari", time: Date(), username: "me")
        c.windowTitle = "Inbox — Mail"
        c.focusedField = "TextField"
        let lines = c.ambientLines
        XCTAssertTrue(lines.contains("Active window: “Inbox — Mail”"))
        XCTAssertTrue(lines.contains("Focused field: TextField"))
        XCTAssertFalse(lines.contains("Selected text"))   // no selection set
    }

    func testAmbientLinesCapsSelectionAt600() {
        var c = GeminiClient.SystemContext(currentApp: "Notes", time: Date(), username: "me")
        c.selection = String(repeating: "a", count: 900)
        let lines = c.ambientLines
        XCTAssertTrue(lines.contains("Selected text:"))
        XCTAssertTrue(lines.contains("…"))
        XCTAssertLessThan(lines.count, 700)   // capped, not the full 900
    }
}
