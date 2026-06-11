import XCTest
@testable import Aria

final class OllamaNativeChatTests: XCTestCase {

    func testParsesContentChunks() {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
        let events = OllamaProvider.events(fromChatLine: Data(line.utf8))
        XCTAssertEqual(events, [.text("Hello")])
    }

    func testParsesToolCalls() {
        let line = #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"open_app","arguments":{"name":"Safari"}}}]},"done":false}"#
        let events = OllamaProvider.events(fromChatLine: Data(line.utf8))
        XCTAssertEqual(events, [.functionCall(name: "open_app", args: ["name": "Safari"])])
    }

    func testIgnoresThinkingAndDoneAndGarbage() {
        XCTAssertTrue(OllamaProvider.events(fromChatLine: Data(#"{"message":{"thinking":"hmm","content":""},"done":false}"#.utf8)).isEmpty)
        XCTAssertTrue(OllamaProvider.events(fromChatLine: Data(#"{"done":true,"total_duration":1}"#.utf8)).isEmpty)
        XCTAssertTrue(OllamaProvider.events(fromChatLine: Data("not json".utf8)).isEmpty)
    }

    func testNonStringArgumentsStringified() {
        let line = #"{"message":{"content":"","tool_calls":[{"function":{"name":"calendar","arguments":{"days":7}}}]},"done":false}"#
        let events = OllamaProvider.events(fromChatLine: Data(line.utf8))
        XCTAssertEqual(events, [.functionCall(name: "calendar", args: ["days": "7"])])
    }
}
