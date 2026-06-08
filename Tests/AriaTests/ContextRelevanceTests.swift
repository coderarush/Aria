import XCTest
@testable import Aria

final class ContextRelevanceTests: XCTestCase {
    func testWantsClipboardOnlyWhenReferenced() {
        XCTAssertTrue(ContextRelevance.wantsClipboard("paste what I copied"))
        XCTAssertTrue(ContextRelevance.wantsClipboard("summarize what's on my clipboard"))
        XCTAssertTrue(ContextRelevance.wantsClipboard("format the thing I just copied"))
        XCTAssertFalse(ContextRelevance.wantsClipboard("what time is it"))
        XCTAssertFalse(ContextRelevance.wantsClipboard("open my notes and start a list"))
    }

    // Clipboard rides along only when set; private clipboard never leaks by default.
    func testAmbientLinesIncludeClipboardOnlyWhenPresent() {
        var ctx = GeminiClient.SystemContext(currentApp: "Notes", time: Date(), username: "u")
        XCTAssertFalse(ctx.ambientLines.contains("Clipboard"))
        ctx.clipboard = "secret token 123"
        XCTAssertTrue(ctx.ambientLines.contains("Clipboard"))
        XCTAssertTrue(ctx.ambientLines.contains("secret token 123"))
    }

    func testAmbientClipboardIsCappedInTheLine() {
        var ctx = GeminiClient.SystemContext(currentApp: "Notes", time: Date(), username: "u")
        ctx.clipboard = String(repeating: "x", count: 2000)
        XCTAssertTrue(ctx.ambientLines.contains("…"))   // truncated, not dumped whole
    }
}
