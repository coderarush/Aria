import XCTest
@testable import Aria

final class OpenAICompatibleClientTests: XCTestCase {
    func testToolsFormat() {
        let specs = [ToolSpec(name: "open_app", description: "Open an app", params: ["name": "app name"])]
        let tools = OpenAICompatibleClient.tools(from: specs)
        XCTAssertEqual(tools.count, 1)
        let fn = tools[0]["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "open_app")
        let params = fn?["parameters"] as? [String: Any]
        let props = params?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["name"])
    }

    func testMessagesIncludesSystemHistoryUser() {
        let history = [ConversationTurn(transcript: "hi", responseMessage: "hello", responseType: .answer)]
        let msgs = OpenAICompatibleClient.messages(system: "You are Aria.", history: history, user: "what time is it")
        XCTAssertEqual(msgs.first?["role"], "system")
        XCTAssertEqual(msgs.last?["role"], "user")
        XCTAssertEqual(msgs.last?["content"], "what time is it")
        XCTAssertTrue(msgs.contains { $0["role"] == "assistant" && $0["content"] == "hello" })
    }

    func testContentTextParsing() {
        let json = #"{"choices":[{"message":{"content":"hello there"}}]}"#
        XCTAssertEqual(OpenAICompatibleClient.contentText(from: Data(json.utf8)), "hello there")
        XCTAssertNil(OpenAICompatibleClient.contentText(from: Data("garbage".utf8)))
    }

    func testToolCallAccumulatorAssemblesStreamedFragments() {
        var acc = OpenAIToolCallAccumulator()
        acc.consume([["index": 0, "function": ["name": "open_app"]]])
        acc.consume([["index": 0, "function": ["arguments": "{\"na"]]])
        acc.consume([["index": 0, "function": ["arguments": "me\":\"Spotify\"}"]]])
        let calls = acc.finalized()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "open_app")
        XCTAssertEqual(calls[0].args["name"], "Spotify")
    }

    func testAccumulatorDropsNamelessCalls() {
        var acc = OpenAIToolCallAccumulator()
        acc.consume([["index": 0, "function": ["arguments": "{}"]]])
        XCTAssertTrue(acc.finalized().isEmpty)
    }
}
