import XCTest
@testable import Aria

final class ModelRouterTests: XCTestCase {
    func testSimpleChatUsesFastModel() {
        XCTAssertEqual(ModelRouter.model(for: "what time is it"), "gemini-2.5-flash-lite")
    }
    func testComplexRequestUsesProModel() {
        XCTAssertEqual(ModelRouter.model(for: "analyze this spreadsheet and write a summary report"), "gemini-2.5-pro")
    }
    func testNeedsScreenshotHeuristic() {
        XCTAssertTrue(ModelRouter.needsScreen(for: "what's on my screen"))
        XCTAssertFalse(ModelRouter.needsScreen(for: "tell me a joke"))
    }
    // Tightened: ambiguous deixis / selection no longer eager-captures — ambient AX
    // covers it and the model escalates via look_at_screen when it truly needs vision.
    func testAmbiguousDeixisDoesNotEagerCapture() {
        XCTAssertFalse(ModelRouter.needsScreen(for: "summarize this"))
        XCTAssertFalse(ModelRouter.needsScreen(for: "translate the selected text"))
        XCTAssertFalse(ModelRouter.needsScreen(for: "reply to her here"))
        XCTAssertTrue(ModelRouter.needsScreen(for: "what's on screen right now"))
    }
    // Planning/recovery use a fast model, never the slow `pro`.
    func testFastStructuredIsALiteModel() {
        XCTAssertEqual(ModelRouter.fastStructured, "gemini-2.5-flash-lite")
        XCTAssertNotEqual(ModelRouter.fastStructured, "gemini-2.5-pro")
    }
}
