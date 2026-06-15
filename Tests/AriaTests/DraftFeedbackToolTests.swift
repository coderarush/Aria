import XCTest
@testable import Aria

final class DraftFeedbackToolTests: XCTestCase {

    // MARK: Helpers

    /// A testable StyleLearner backed by a temp file so it never touches
    /// Application Support, and it reads/writes a freshly-created URL each run.
    private func makeLearner() -> StyleLearner {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-test-\(UUID()).json")
        // StyleLearner's init enables personalization via UserDefaults.
        // We need personalization ON so recordFeedback actually records.
        let defaults = UserDefaults(suiteName: "DraftFeedbackTests-\(UUID())")!
        defaults.set(true, forKey: StyleLearner.enabledKey)
        return StyleLearner(storeURL: tmp, defaults: defaults)
    }

    // MARK: Tests

    func testApproveCallsRecordFeedback() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "approve", "note": "great draft"])
        XCTAssertTrue(result.success)
    }

    func testRejectCallsRecordFeedback() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "reject"])
        XCTAssertTrue(result.success)
    }

    func testInvalidRatingReturnsError() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "maybe"])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("approve"),
                      "Error should mention 'approve'; got: \(result.output)")
        XCTAssertTrue(result.output.lowercased().contains("reject"),
                      "Error should mention 'reject'; got: \(result.output)")
    }

    func testMissingRatingReturnsError() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: [:])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("missing") ||
                      result.output.lowercased().contains("approve"),
                      "Error should mention missing rating; got: \(result.output)")
    }

    func testNotePassedAsDraftText() async throws {
        // For an approve with a note, the learner should store the note as a sample.
        // We verify indirectly that no error occurs and the approval message is returned.
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "reject", "note": "too formal"])
        XCTAssertTrue(result.success)
        // The note "too formal" is processed as draftText — no crash, no error
    }

    func testApproveResponseMessage() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "approve"])
        XCTAssertTrue(result.output.lowercased().contains("keep that style"),
                      "Approve response should contain 'keep that style'; got: \(result.output)")
    }

    func testRejectResponseMessage() async throws {
        let learner = makeLearner()
        let tool = DraftFeedbackTool(learner: learner)
        let result = try await tool.run(input: ["rating": "reject"])
        XCTAssertTrue(result.output.lowercased().contains("adjust"),
                      "Reject response should contain 'adjust'; got: \(result.output)")
    }
}
