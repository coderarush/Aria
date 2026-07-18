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

    func testParsesWhitelistedVerificationContracts() {
        let json = """
        [{"summary":"Open Notes","tool":"open_app","input":{"name":"Notes"},"verify":{"kind":"app_running","name":"Notes"}},
         {"summary":"Close Mail","tool":"quit_app","input":{"name":"Mail"},"verify":{"kind":"app_not_running","name":"Mail"}},
         {"summary":"Save draft","tool":"file_write","input":{"path":"/tmp/draft.md"},"verify":{"kind":"file_exists","path":"/tmp/draft.md"}},
         {"summary":"Ignore malformed file check","tool":"file_write","verify":{"kind":"file_exists","path":"   "}},
         {"summary":"Ignore unrelated file check","tool":"file_write","input":{"path":"/tmp/draft.md"},"verify":{"kind":"file_exists","path":"/tmp/unrelated.md"}},
         {"summary":"Ignore unknown","tool":"open_app","verify":{"kind":"screenshot_matches","name":"x"}}]
        """
        let steps = PlanParser.steps(fromJSON: json)
        XCTAssertEqual(steps[0].postCondition, .appRunning("Notes"))
        XCTAssertEqual(steps[1].postCondition, .appNotRunning("Mail"))
        XCTAssertEqual(steps[2].postCondition, .fileExists("/tmp/draft.md"))
        XCTAssertEqual(steps[3].postCondition, .none)
        XCTAssertEqual(steps[4].postCondition, .none)
        XCTAssertEqual(steps[5].postCondition, .none)
    }
}
