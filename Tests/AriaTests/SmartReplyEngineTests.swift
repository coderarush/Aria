import XCTest
@testable import Aria

final class SmartReplyEngineTests: XCTestCase {
    private let engine = SmartReplyEngine()

    // MARK: - Valid JSON

    func testGeneratesThreeReplies() async throws {
        let json = """
[{"text":"Got it.","tone":"brief"},{"text":"Thanks so much!","tone":"friendly"},{"text":"Thank you for your message.","tone":"formal"}]
"""
        let replies = try await engine.generate(
            emailSubject: "Meeting request",
            emailBody: "Can we meet tomorrow?",
            from: "alice@example.com",
            synthesize: { _ in json }
        )
        XCTAssertEqual(replies.count, 3)
    }

    func testThrowsOnFewerThanThree() async throws {
        let json = """
[{"text":"Got it.","tone":"brief"},{"text":"Thanks!","tone":"friendly"}]
"""
        do {
            _ = try await engine.generate(
                emailSubject: "Hi",
                emailBody: "Hello",
                from: "bob@example.com",
                synthesize: { _ in json }
            )
            XCTFail("Expected parseFailure")
        } catch SmartReplyError.parseFailure {
            // expected
        }
    }

    func testThrowsOnBadJSON() async throws {
        do {
            _ = try await engine.generate(
                emailSubject: "Test",
                emailBody: "body",
                from: "x@y.com",
                synthesize: { _ in "not json at all" }
            )
            XCTFail("Expected parseFailure")
        } catch SmartReplyError.parseFailure {
            // expected
        }
    }

    func testTonesArePreserved() async throws {
        let json = """
[{"text":"Short.","tone":"brief"},{"text":"Hey friend!","tone":"friendly"},{"text":"Dear Sir/Madam,","tone":"formal"}]
"""
        let replies = try await engine.generate(
            emailSubject: "Hello",
            emailBody: "World",
            from: "sender@example.com",
            synthesize: { _ in json }
        )
        let tones = replies.map { $0.tone }
        XCTAssertEqual(tones, ["brief", "friendly", "formal"])
    }

    func testEmptyEmailFields() async throws {
        // All empty strings — engine should still forward the prompt and parse
        let json = """
[{"text":"A","tone":"brief"},{"text":"B","tone":"friendly"},{"text":"C","tone":"formal"}]
"""
        let replies = try await engine.generate(
            emailSubject: "",
            emailBody: "",
            from: "",
            synthesize: { _ in json }
        )
        XCTAssertEqual(replies.count, 3)
    }

    // MARK: - JSON embedded in extra prose

    func testExtractsJSONFromProse() async throws {
        // The model sometimes wraps the array in prose; the engine should still parse it.
        let raw = """
Here are your replies:
[{"text":"Sure.","tone":"brief"},{"text":"Of course!","tone":"friendly"},{"text":"Certainly.","tone":"formal"}]
"""
        let replies = try await engine.generate(
            emailSubject: "Follow up",
            emailBody: "Did you get my message?",
            from: "y@z.com",
            synthesize: { _ in raw }
        )
        XCTAssertEqual(replies.count, 3)
    }
}
