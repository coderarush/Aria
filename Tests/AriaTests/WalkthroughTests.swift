import XCTest
@testable import Aria

final class WalkthroughTests: XCTestCase {

    func testIntentExtractsTask() {
        XCTAssertEqual(WalkthroughIntent.task(for: "walk me through exporting a PDF"), "exporting a pdf")
        XCTAssertEqual(WalkthroughIntent.task(for: "Show me how to add a keyframe"), "add a keyframe")
        XCTAssertEqual(WalkthroughIntent.task(for: "guide me through: setting up a layer"), "setting up a layer")
    }

    func testIntentIgnoresPlainQuestions() {
        XCTAssertNil(WalkthroughIntent.task(for: "what is a keyframe"))
        XCTAssertNil(WalkthroughIntent.task(for: "export this as a pdf"))
        XCTAssertNil(WalkthroughIntent.task(for: "walk me through"))   // no task
    }

    func testParseCleanArray() {
        let raw = """
        [{"element":"File menu","instruction":"Click File"},
         {"element":"Export item","instruction":"Choose Export"}]
        """
        let steps = WalkthroughPlan.parse(raw)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].element, "File menu")
        XCTAssertEqual(steps[1].instruction, "Choose Export")
    }

    func testParseFencedAndAlternateKeys() {
        let raw = """
        ```json
        [{"target":"the Share button","do":"Press Share"}]
        ```
        """
        let steps = WalkthroughPlan.parse(raw)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].element, "the Share button")
        XCTAssertEqual(steps[0].instruction, "Press Share")
    }

    func testParseCapsStepsAndSkipsEmpty() {
        let items = (1...10).map { "{\"element\":\"e\($0)\",\"instruction\":\"do \($0)\"}" }.joined(separator: ",")
        let steps = WalkthroughPlan.parse("[\(items)]", maxSteps: 4)
        XCTAssertEqual(steps.count, 4)
    }

    func testParseGarbageReturnsEmpty() {
        XCTAssertTrue(WalkthroughPlan.parse("sorry, I can't help").isEmpty)
        XCTAssertTrue(WalkthroughPlan.parse("").isEmpty)
    }
}
