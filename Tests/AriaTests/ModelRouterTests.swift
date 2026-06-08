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
    // Planning/recovery use a fast model, never the slow `pro`.
    func testFastStructuredIsALiteModel() {
        XCTAssertEqual(ModelRouter.fastStructured, "gemini-2.5-flash-lite")
        XCTAssertNotEqual(ModelRouter.fastStructured, "gemini-2.5-pro")
    }
}
