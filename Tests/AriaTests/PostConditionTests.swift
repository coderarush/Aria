import XCTest
@testable import Aria

final class PostConditionTests: XCTestCase {
    func testResultContainsPasses() {
        XCTAssertTrue(PostCondition.resultContains("ok").isSatisfied(byResult: "all ok here", ok: true))
        XCTAssertFalse(PostCondition.resultContains("ok").isSatisfied(byResult: "failed", ok: true))
    }
    func testResultContainsRequiresOk() {
        XCTAssertFalse(PostCondition.resultContains("ok").isSatisfied(byResult: "ok", ok: false))
    }
    func testSucceededChecksOkFlag() {
        XCTAssertTrue(PostCondition.succeeded.isSatisfied(byResult: "anything", ok: true))
        XCTAssertFalse(PostCondition.succeeded.isSatisfied(byResult: "anything", ok: false))
    }
    func testNoneAlwaysPasses() {
        XCTAssertTrue(PostCondition.none.isSatisfied(byResult: "", ok: false))
    }
    func testCodableRoundTrip() throws {
        let pc = PostCondition.resultContains("done")
        let back = try JSONDecoder().decode(PostCondition.self, from: JSONEncoder().encode(pc))
        XCTAssertEqual(back, pc)
    }
}
