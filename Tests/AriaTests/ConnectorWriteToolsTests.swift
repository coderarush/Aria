import XCTest
@testable import Aria

// MARK: - Pure request-body construction (Gmail RFC822/base64url, Calendar JSON)

final class GoogleWriteBodyTests: XCTestCase {

    /// base64url decode helper (no padding) so we can prove round-trips.
    private func decodeBase64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    func testBase64urlHasNoPaddingOrUnsafeChars() {
        // "sure." → base64 "c3VyZS4=" (one pad char) → base64url drops the pad.
        let enc = GoogleConnector.base64url(Data("sure.".utf8))
        XCTAssertFalse(enc.contains("="))
        XCTAssertFalse(enc.contains("+"))
        XCTAssertFalse(enc.contains("/"))
        XCTAssertEqual(decodeBase64url(enc), Data("sure.".utf8))
    }

    func testGmailRawMessageIsValidRFC822AndRoundTrips() throws {
        let raw = GoogleConnector.gmailRawMessage(
            to: "alice@example.com", subject: "Launch", body: "Shipping today.")
        let decoded = try XCTUnwrap(decodeBase64url(raw))
        let mime = String(decoding: decoded, as: UTF8.self)
        // Headers present, CRLF separated, blank line before the body.
        XCTAssertTrue(mime.contains("To: alice@example.com"))
        XCTAssertTrue(mime.contains("Subject: Launch"))
        XCTAssertTrue(mime.contains("MIME-Version: 1.0"))
        XCTAssertTrue(mime.contains("\r\n\r\nShipping today."))
        XCTAssertTrue(mime.contains("\r\n"))   // CRLF line endings, not bare \n
    }

    func testGmailSendBodyWrapsRawAtTopLevel() throws {
        let body = GoogleConnector.gmailSendBody(to: "a@b.com", subject: "Hi", body: "Yo")
        let raw = try XCTUnwrap(body["raw"] as? String)
        // The send API expects `{"raw": ...}` with no nesting.
        XCTAssertNil(body["message"])
        let mime = String(decoding: try XCTUnwrap(decodeBase64url(raw)), as: UTF8.self)
        XCTAssertTrue(mime.contains("To: a@b.com"))
        // Serializes to valid JSON.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testGmailDraftBodyNestsRawUnderMessage() throws {
        let body = GoogleConnector.gmailDraftBody(to: "a@b.com", subject: "Hi", body: "Yo")
        // The drafts API expects `{"message": {"raw": ...}}`.
        let message = try XCTUnwrap(body["message"] as? [String: Any])
        let raw = try XCTUnwrap(message["raw"] as? String)
        let mime = String(decoding: try XCTUnwrap(decodeBase64url(raw)), as: UTF8.self)
        XCTAssertTrue(mime.contains("Subject: Hi"))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testCalendarEventBodyShape() throws {
        let body = GoogleConnector.calendarEventBody(
            title: "Standup", start: "2026-06-20T15:00:00Z", end: "2026-06-20T15:30:00Z")
        XCTAssertEqual(body["summary"] as? String, "Standup")
        let start = try XCTUnwrap(body["start"] as? [String: Any])
        let end = try XCTUnwrap(body["end"] as? [String: Any])
        XCTAssertEqual(start["dateTime"] as? String, "2026-06-20T15:00:00Z")
        XCTAssertEqual(end["dateTime"] as? String, "2026-06-20T15:30:00Z")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}

// MARK: - Pure write-response parsing (server id extraction)

final class GoogleWriteParseTests: XCTestCase {

    func testParsesSentMessageID() {
        let json = #"{"id":"18f0aa","threadId":"18f0aa","labelIds":["SENT"]}"#
        XCTAssertEqual(GoogleConnector.parseGmailWriteID(Data(json.utf8)), "18f0aa")
    }

    func testParsesDraftID() {
        // A drafts.create response: top-level id is the draft id.
        let json = #"{"id":"r-123","message":{"id":"m-9","threadId":"t-9"}}"#
        XCTAssertEqual(GoogleConnector.parseDraftID(Data(json.utf8)), "r-123")
    }

    func testParsesCalendarEventID() {
        let json = #"{"kind":"calendar#event","id":"evt_42","status":"confirmed"}"#
        XCTAssertEqual(GoogleConnector.parseCalendarEventID(Data(json.utf8)), "evt_42")
    }

    func testMalformedResponsesYieldNil() {
        XCTAssertNil(GoogleConnector.parseGmailWriteID(Data("not json".utf8)))
        XCTAssertNil(GoogleConnector.parseDraftID(Data("{}".utf8)))
        XCTAssertNil(GoogleConnector.parseCalendarEventID(Data("[]".utf8)))
    }
}

// MARK: - Not-connected tool behavior (no network, no token)

final class WriteToolNotConnectedTests: XCTestCase {

    /// A ConnectorStore backed by an empty token store → validAccessToken == nil.
    private func emptyStore() -> ConnectorStore {
        ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0,
                                     scopes: [], tokenType: "Bearer")
            })
    }

    func testGmailSendNotConnectedReturnsCleanMessage() async throws {
        let tool = GmailSendTool(store: emptyStore())
        let result = try await tool.run(input: ["to": "a@b.com", "body": "hi"])
        XCTAssertTrue(result.success)  // clean message, never a crash
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Gmail"))
    }

    func testGmailSendMissingRecipientThrowsBeforeNetwork() async {
        let tool = GmailSendTool(store: emptyStore())
        do {
            _ = try await tool.run(input: ["body": "hi"])
            XCTFail("expected missingInput for empty recipient")
        } catch ToolError.missingInput(let field) {
            XCTAssertEqual(field, "to")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGmailDraftNotConnectedReturnsCleanMessage() async throws {
        let tool = GmailDraftTool(store: emptyStore())
        let result = try await tool.run(input: ["to": "a@b.com", "body": "hi"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Gmail"))
    }

    func testGcalCreateNotConnectedReturnsCleanMessage() async throws {
        let tool = GcalCreateTool(store: emptyStore())
        let result = try await tool.run(input: [
            "title": "Sync", "start": "2026-06-20T15:00:00Z", "end": "2026-06-20T15:30:00Z"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Calendar"))
    }

    func testGcalCreateMissingFieldsThrowBeforeNetwork() async {
        let tool = GcalCreateTool(store: emptyStore())
        for missing in [["start": "x", "end": "y"], ["title": "t", "end": "y"], ["title": "t", "start": "x"]] {
            do {
                _ = try await tool.run(input: missing)
                XCTFail("expected missingInput for \(missing)")
            } catch is ToolError {
                // expected — required field absent
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Safety classification of the new write tools

final class WriteToolSafetyTests: XCTestCase {

    func testGmailSendIsImportantIrreversible() {
        // External comms → gates under high autonomy.
        XCTAssertEqual(
            Safety.importance(tool: "gmail_send",
                              input: ["to": "a@b.com", "body": "hi"], summary: "send a gmail"),
            .importantIrreversible)
        XCTAssertTrue(Safety.importantTools.contains("gmail_send"))
        XCTAssertTrue(GmailSendTool().isDestructive)
    }

    func testGmailDraftDoesNotGate() {
        // A draft isn't sent — routine, even if the body contains a danger word.
        XCTAssertEqual(
            Safety.importance(tool: "gmail_draft",
                              input: ["body": "send the report and delete the file"],
                              summary: "draft a gmail"),
            .routine)
        XCTAssertFalse(GmailDraftTool().isDestructive)
    }

    func testGcalCreateDoesNotGate() {
        // An event can be deleted — routine, even with a danger word in the title.
        XCTAssertEqual(
            Safety.importance(tool: "gcal_create",
                              input: ["title": "send-off party", "start": "x", "end": "y"],
                              summary: "create a calendar event"),
            .routine)
        XCTAssertFalse(GcalCreateTool().isDestructive)
    }
}
