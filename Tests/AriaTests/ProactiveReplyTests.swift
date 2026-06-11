import XCTest
@testable import Aria

final class ProactiveReplyTests: XCTestCase {

    func testAffirmatives() {
        for s in ["yes", "Yeah", "yep", "sure", "do it", "go ahead", "please do",
                  "ok", "okay", "sounds good", "Yes please"] {
            XCTAssertTrue(ProactiveReply.isAffirmative(s), "expected affirmative: \(s)")
        }
    }

    func testNegativesAndUnrelated() {
        for s in ["no", "not now", "nah", "stop", "what's the weather", "open safari", ""] {
            XCTAssertFalse(ProactiveReply.isAffirmative(s), "expected non-affirmative: \(s)")
        }
    }
}
