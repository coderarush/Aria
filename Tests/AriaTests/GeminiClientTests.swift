import XCTest
@testable import Aria

final class GeminiClientTests: XCTestCase {

    /// Gemini envelope wrapping a well-formed AriaResponse JSON string.
    func testDecodeWellFormedResponse() throws {
        let inner = #"{"type":"answer","message":"Hello there","confidence":0.9,"actions":[],"followup":null}"#
        let envelope = """
        { "candidates": [ { "content": { "parts": [ { "text": \(jsonString(inner)) } ] } } ] }
        """
        let data = Data(envelope.utf8)
        let response = try GeminiClient.decodeAriaResponse(from: data)
        XCTAssertEqual(response.type, .answer)
        XCTAssertEqual(response.message, "Hello there")
        XCTAssertEqual(response.confidence, 0.9, accuracy: 0.0001)
    }

    /// Multi-action responses decode their actions array.
    func testDecodeMultiAction() throws {
        let inner = #"{"type":"multi_action","message":"Working","confidence":0.8,"actions":[{"tool":"open_app","input":{"name":"Safari"}}]}"#
        let envelope = """
        { "candidates": [ { "content": { "parts": [ { "text": \(jsonString(inner)) } ] } } ] }
        """
        let response = try GeminiClient.decodeAriaResponse(from: Data(envelope.utf8))
        XCTAssertEqual(response.type, .multiAction)
        XCTAssertEqual(response.actions.first?.tool, "open_app")
        XCTAssertEqual(response.actions.first?.input["name"], "Safari")
    }

    /// When the model returns plain text (not JSON), it is wrapped as an answer.
    func testDecodeNonJSONFallsBackToAnswer() throws {
        let envelope = """
        { "candidates": [ { "content": { "parts": [ { "text": "just some text" } ] } } ] }
        """
        let response = try GeminiClient.decodeAriaResponse(from: Data(envelope.utf8))
        XCTAssertEqual(response.type, .answer)
        XCTAssertEqual(response.message, "just some text")
    }

    /// Missing confidence/actions default gracefully.
    func testLenientDefaults() throws {
        let inner = #"{"type":"clarify","message":"Which file?"}"#
        let envelope = """
        { "candidates": [ { "content": { "parts": [ { "text": \(jsonString(inner)) } ] } } ] }
        """
        let response = try GeminiClient.decodeAriaResponse(from: Data(envelope.utf8))
        XCTAssertEqual(response.type, .clarify)
        XCTAssertEqual(response.confidence, 1.0)
        XCTAssertTrue(response.actions.isEmpty)
    }

    func testEmptyEnvelopeThrows() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try GeminiClient.decodeAriaResponse(from: data))
    }

    func testSystemPromptIsAriaConversationalPersona() {
        let p = GeminiClient.systemPrompt
        XCTAssertTrue(p.contains("Aria"))
        XCTAssertFalse(p.contains("Friday"))
        let lower = p.lowercased()
        XCTAssertTrue(lower.contains("confident"))
        XCTAssertTrue(lower.contains("charming") || lower.contains("charm"))
        XCTAssertTrue(lower.contains("spoken") || lower.contains("conversation"))
        XCTAssertTrue(lower.contains("tool"))   // mentions using tools/functions
    }

    // Encode a string as a JSON string literal (with quotes + escaping).
    private func jsonString(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(decoding: data, as: UTF8.self)
    }
}
