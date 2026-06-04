import XCTest
@testable import Aria

final class PlanParserTests: XCTestCase {
    func testParsesStepsWithToolAndAgentExecutors() {
        let json = """
        [{"summary":"Search mics","agent":"Orion","input":{"query":"best usb mics"}},
         {"summary":"Open Notes","tool":"open_app","input":{"name":"Notes"}}]
        """
        let steps = PlanParser.steps(fromJSON: json)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].executor, .agent("Orion"))
        XCTAssertEqual(steps[0].input["query"], "best usb mics")
        XCTAssertEqual(steps[1].executor, .tool("open_app"))
    }
    func testReturnsEmptyOnGarbage() {
        XCTAssertTrue(PlanParser.steps(fromJSON: "not json").isEmpty)
    }
}
