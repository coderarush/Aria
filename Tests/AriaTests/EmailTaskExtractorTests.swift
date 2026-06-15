import XCTest
@testable import Aria

final class EmailTaskExtractorTests: XCTestCase {

    private let extractor = EmailTaskExtractor()

    func testExtractFindsCommitment() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in
            """
            [{"commitment":"Send the report by Friday","deadline":"Friday","source":"Project Update"}]
            """
        }
        let tasks = try await extractor.extract(
            emails: ["Subject: Project Update\nFrom: boss@co.com\n\nBody: Please send the report by Friday."],
            synthesize: synthesize
        )
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].commitment, "Send the report by Friday")
        XCTAssertEqual(tasks[0].deadline, "Friday")
        XCTAssertEqual(tasks[0].source, "Project Update")
    }

    func testExtractReturnsEmptyForNoCommitments() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in "[]" }
        let tasks = try await extractor.extract(
            emails: ["Subject: FYI\nFrom: noreply@co.com\n\nBody: Nothing to act on."],
            synthesize: synthesize
        )
        XCTAssertTrue(tasks.isEmpty)
    }

    func testExtractThrowsOnBadJSON() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in "not json at all" }
        do {
            _ = try await extractor.extract(emails: ["Subject: Test\nFrom: a@b.com\n\nBody: x"], synthesize: synthesize)
            XCTFail("Expected parseFailure to be thrown")
        } catch EmailTaskError.parseFailure {
            // expected
        }
    }

    func testExtractMultipleEmails() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in
            """
            [
              {"commitment":"Follow up with John","source":"Meeting Notes"},
              {"commitment":"Review PR #42","deadline":"tomorrow","source":"Code Review Request"}
            ]
            """
        }
        let emails = [
            "Subject: Meeting Notes\nFrom: a@co.com\n\nBody: Follow up with John.",
            "Subject: Code Review Request\nFrom: b@co.com\n\nBody: Review PR #42 by tomorrow.",
            "Subject: Newsletter\nFrom: news@co.com\n\nBody: Check out this week's updates."
        ]
        let tasks = try await extractor.extract(emails: emails, synthesize: synthesize)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].commitment, "Follow up with John")
        XCTAssertEqual(tasks[1].commitment, "Review PR #42")
        XCTAssertEqual(tasks[1].deadline, "tomorrow")
    }

    func testExtractHandlesMissingDeadline() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in
            """
            [{"commitment":"Reply to Alice","source":"Hello"}]
            """
        }
        let tasks = try await extractor.extract(
            emails: ["Subject: Hello\nFrom: alice@co.com\n\nBody: Let me know."],
            synthesize: synthesize
        )
        XCTAssertEqual(tasks.count, 1)
        XCTAssertNil(tasks[0].deadline)
    }

    func testExtractPassesEmailContentToSynthesize() async throws {
        var capturedPrompt = ""
        let synthesize: @Sendable (String) async throws -> String = { prompt in
            capturedPrompt = prompt
            return "[]"
        }
        let emails = ["Subject: Test Email\nFrom: sender@co.com\n\nBody: Important task here."]
        _ = try await extractor.extract(emails: emails, synthesize: synthesize)
        XCTAssertTrue(capturedPrompt.contains("Test Email"))
        XCTAssertTrue(capturedPrompt.contains("task extractor"))
    }
}
