import XCTest
@testable import Aria

// MARK: - Notion pure request-body construction

final class NotionBodyTests: XCTestCase {

    func testSearchBodyIncludesQueryWhenPresent() throws {
        let body = NotionConnector.searchBody(query: "launch plan", pageSize: 5)
        XCTAssertEqual(body["query"] as? String, "launch plan")
        XCTAssertEqual(body["page_size"] as? Int, 5)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testSearchBodyOmitsEmptyQuery() {
        // An empty/whitespace query is dropped so Notion returns recent items.
        let body = NotionConnector.searchBody(query: "   ", pageSize: 10)
        XCTAssertNil(body["query"])
        XCTAssertEqual(body["page_size"] as? Int, 10)
    }

    func testSearchBodyClampsPageSize() {
        XCTAssertEqual(NotionConnector.searchBody(query: "x", pageSize: 999)["page_size"] as? Int, 100)
        XCTAssertEqual(NotionConnector.searchBody(query: "x", pageSize: 0)["page_size"] as? Int, 1)
    }

    func testAppendBodyShapesParagraphRichText() throws {
        let body = NotionConnector.appendBody(text: "shipping today")
        let children = try XCTUnwrap(body["children"] as? [[String: Any]])
        let block = try XCTUnwrap(children.first)
        XCTAssertEqual(block["type"] as? String, "paragraph")
        let paragraph = try XCTUnwrap(block["paragraph"] as? [String: Any])
        let richText = try XCTUnwrap(paragraph["rich_text"] as? [[String: Any]])
        let run = try XCTUnwrap(richText.first)
        let textObj = try XCTUnwrap(run["text"] as? [String: Any])
        XCTAssertEqual(textObj["content"] as? String, "shipping today")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}

// MARK: - Notion pure response parsing

final class NotionParseTests: XCTestCase {

    func testParsesPageTitleFromProperties() {
        let json = #"""
        {"results":[{"object":"page","id":"p1","url":"https://n/p1",
          "properties":{"Name":{"type":"title","title":[{"plain_text":"Launch Plan"}]}}}]}
        """#
        let hits = NotionConnector.parseSearchResults(Data(json.utf8))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].id, "p1")
        XCTAssertEqual(hits[0].kind, .page)
        XCTAssertEqual(hits[0].title, "Launch Plan")
    }

    func testParsesDatabaseTitleFromTopLevel() {
        let json = #"""
        {"results":[{"object":"database","id":"d1","url":"https://n/d1",
          "title":[{"plain_text":"Tasks"}]}]}
        """#
        let hits = NotionConnector.parseSearchResults(Data(json.utf8))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].kind, .database)
        XCTAssertEqual(hits[0].title, "Tasks")
    }

    func testUntitledFallback() {
        let json = #"{"results":[{"object":"page","id":"p2","properties":{}}]}"#
        let hits = NotionConnector.parseSearchResults(Data(json.utf8))
        XCTAssertEqual(hits[0].title, "(untitled)")
    }

    func testParseSearchMalformedYieldsEmpty() {
        XCTAssertTrue(NotionConnector.parseSearchResults(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(NotionConnector.parseSearchResults(Data("{}".utf8)).isEmpty)
    }

    func testParseAppendedParentIDFromResults() {
        let json = #"{"object":"list","results":[{"id":"blk_1"}]}"#
        XCTAssertEqual(NotionConnector.parseAppendedParentID(Data(json.utf8)), "blk_1")
    }

    func testFormatSearchEmptyAndPopulated() {
        XCTAssertEqual(NotionConnector.formatSearch([]), "No matching Notion pages or databases.")
        let out = NotionConnector.formatSearch([
            .init(id: "x", kind: .page, title: "Plan", url: "")])
        XCTAssertTrue(out.contains("Plan"))
        XCTAssertTrue(out.contains("[page]"))
    }
}

// MARK: - Slack pure request-body construction

final class SlackBodyTests: XCTestCase {

    func testPostMessageBodyShape() throws {
        let body = SlackConnector.postMessageBody(channel: "C123", text: "hello team")
        XCTAssertEqual(body["channel"] as? String, "C123")
        XCTAssertEqual(body["text"] as? String, "hello team")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}

// MARK: - Slack pure response parsing (ok-aware)

final class SlackParseTests: XCTestCase {

    func testParsesHistoryKeepsUserMessages() {
        let json = #"""
        {"ok":true,"messages":[
          {"type":"message","user":"U1","text":"hi","ts":"1.1"},
          {"type":"message","subtype":"channel_join","text":"joined","ts":"1.0"}
        ]}
        """#
        let msgs = SlackConnector.parseHistory(Data(json.utf8))
        XCTAssertEqual(msgs.count, 2)   // both have text; subtype kept (user falls back)
        XCTAssertEqual(msgs[0].user, "U1")
        XCTAssertEqual(msgs[0].text, "hi")
    }

    func testParseHistoryDropsEmptyTextAndNotOK() {
        XCTAssertTrue(SlackConnector.parseHistory(Data(#"{"ok":false,"error":"x"}"#.utf8)).isEmpty)
        let json = #"{"ok":true,"messages":[{"type":"message","user":"U1","text":"","ts":"1"}]}"#
        XCTAssertTrue(SlackConnector.parseHistory(Data(json.utf8)).isEmpty)
    }

    func testParseSendResultRequiresOK() {
        let ok = #"{"ok":true,"channel":"C1","ts":"123.45"}"#
        let result = SlackConnector.parseSendResult(Data(ok.utf8))
        XCTAssertEqual(result?.channel, "C1")
        XCTAssertEqual(result?.ts, "123.45")
        XCTAssertNil(SlackConnector.parseSendResult(Data(#"{"ok":false,"error":"no"}"#.utf8)))
        XCTAssertNil(SlackConnector.parseSendResult(Data("garbage".utf8)))
    }

    func testThrowIfNotOK() {
        XCTAssertThrowsError(try SlackConnector.throwIfNotOK(Data(#"{"ok":false}"#.utf8)))
        XCTAssertThrowsError(try SlackConnector.throwIfNotOK(Data("nope".utf8)))
        XCTAssertNoThrow(try SlackConnector.throwIfNotOK(Data(#"{"ok":true}"#.utf8)))
    }

    func testFormatMessagesEmptyAndPopulated() {
        XCTAssertEqual(SlackConnector.formatMessages([]),
                       "No recent Slack messages in that channel.")
        let out = SlackConnector.formatMessages([.init(user: "U1", text: "yo", ts: "1")])
        XCTAssertTrue(out.contains("U1"))
        XCTAssertTrue(out.contains("yo"))
    }
}

// MARK: - Not-connected tool behavior (no network, no token)

final class NotionSlackNotConnectedTests: XCTestCase {

    private func emptyStore() -> ConnectorStore {
        ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0,
                                     scopes: [], tokenType: "Bearer")
            })
    }

    func testNotionSearchNotConnected() async throws {
        let result = try await NotionSearchTool(store: emptyStore()).run(input: ["query": "x"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Notion"))
    }

    func testNotionAppendNotConnected() async throws {
        let result = try await NotionAppendTool(store: emptyStore())
            .run(input: ["page_id": "p1", "text": "note"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Notion"))
    }

    func testNotionAppendMissingFieldsThrowBeforeNetwork() async {
        let tool = NotionAppendTool(store: emptyStore())
        for missing in [["text": "note"], ["page_id": "p1"]] {
            do {
                _ = try await tool.run(input: missing)
                XCTFail("expected missingInput for \(missing)")
            } catch is ToolError {
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testSlackRecentNotConnected() async throws {
        let result = try await SlackRecentTool(store: emptyStore()).run(input: ["channel": "C1"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Slack"))
    }

    func testSlackRecentMissingChannelThrows() async {
        do {
            _ = try await SlackRecentTool(store: emptyStore()).run(input: [:])
            XCTFail("expected missingInput")
        } catch ToolError.missingInput(let field) {
            XCTAssertEqual(field, "channel")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSlackSendNotConnected() async throws {
        let result = try await SlackSendTool(store: emptyStore())
            .run(input: ["channel": "C1", "text": "hi"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Slack"))
    }

    func testSlackSendMissingFieldsThrowBeforeNetwork() async {
        let tool = SlackSendTool(store: emptyStore())
        for missing in [["text": "hi"], ["channel": "C1"]] {
            do {
                _ = try await tool.run(input: missing)
                XCTFail("expected missingInput for \(missing)")
            } catch is ToolError {
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Safety classification of the new tools

final class NotionSlackSafetyTests: XCTestCase {

    func testReadsAndNotionAppendAreRoutine() {
        for tool in ["notion_search", "slack_recent"] {
            XCTAssertEqual(
                Safety.importance(tool: tool, input: ["query": "post the update"],
                                  summary: "read"),
                .routine, "\(tool) should not gate")
        }
        // notion_append is reversible-ish → routine, even with a danger word.
        XCTAssertEqual(
            Safety.importance(tool: "notion_append",
                              input: ["text": "send the report and delete the file"],
                              summary: "append a note"),
            .routine)
        XCTAssertFalse(NotionAppendTool().isDestructive)
    }

    func testSlackSendIsImportantIrreversible() {
        XCTAssertEqual(
            Safety.importance(tool: "slack_send",
                              input: ["channel": "C1", "text": "hi"], summary: "post to slack"),
            .importantIrreversible)
        XCTAssertTrue(Safety.importantTools.contains("slack_send"))
        XCTAssertTrue(SlackSendTool().isDestructive)
    }
}
