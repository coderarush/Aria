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
        for condition in [PostCondition.none, .succeeded, .resultContains("done"),
                          .appRunning("Notes"), .appNotRunning("Mail"),
                          .fileExists("/tmp/draft.md")] {
            let back = try JSONDecoder().decode(PostCondition.self, from: JSONEncoder().encode(condition))
            XCTAssertEqual(back, condition)
        }
    }

    func testAppStateConditionsDescribeExpectedEffect() {
        XCTAssertEqual(PostCondition.appRunning("Notes").expectation, "Notes is running")
        XCTAssertEqual(PostCondition.appNotRunning("Mail").expectation, "Mail is no longer running")
    }

    func testFileConditionUsesInjectedFileStateWithoutReadingContents() async {
        let verifier = PostConditionVerifier(
            isAppRunning: { _ in false },
            fileExists: { path in path == "/tmp/draft.md" },
            attempts: 1,
            retryDelayNanoseconds: 0)

        let present = await verifier.verify(.fileExists("/tmp/draft.md"), result: .ok("Saved."))
        let missing = await verifier.verify(.fileExists("/tmp/missing.md"), result: .ok("Saved."))

        XCTAssertEqual(PostCondition.fileExists("/tmp/draft.md").expectation, "the file exists")
        XCTAssertTrue(present.passed)
        XCTAssertEqual(present.proof, "Confirmed the file exists.")
        XCTAssertFalse(missing.passed)
        XCTAssertEqual(missing.proof, "Couldn't confirm the file exists.")
    }

    func testAppStateVerifierUsesInjectedAppStateAndNormalizesAppNames() async {
        let verifier = PostConditionVerifier(
            isAppRunning: { app in PostConditionVerifier.appNameMatches(running: "Notes", expected: app) },
            attempts: 1,
            retryDelayNanoseconds: 0)

        let opened = await verifier.verify(.appRunning("notes.app"), result: .ok("Opened Notes."))
        XCTAssertTrue(opened.passed)
        XCTAssertEqual(opened.proof, "Confirmed Notes is running.")

        let closed = await verifier.verify(.appNotRunning("Notes"), result: .ok("Quit Notes."))
        XCTAssertFalse(closed.passed)
        XCTAssertEqual(closed.proof, "Couldn't confirm Notes closed.")
    }

    func testFailedToolNeverPassesAnExplicitCondition() async {
        let verifier = PostConditionVerifier(isAppRunning: { _ in true }, attempts: 1, retryDelayNanoseconds: 0)
        let check = await verifier.verify(.appRunning("Notes"), result: .fail("launch failed"))
        XCTAssertFalse(check.passed)
        XCTAssertEqual(check.proof, "Tool did not complete successfully.")
    }
}
