import XCTest
@testable import Aria

/// v11.1.1 — undoable connector writes: a created Gmail draft / Calendar event
/// must be reversible from the Receipts pane. These cover the new
/// `ReversibleAction` cases (Codable + label), the pure DELETE-URL builders, and
/// the no-token revert contract. No test touches the network.
final class UndoableConnectorWritesTests: XCTestCase {

    // MARK: - ReversibleAction Codable round-trip (new cases)

    func testGmailDraftCreatedCodableRoundTrip() throws {
        let action = ReversibleAction.gmailDraftCreated(id: "r-9f8c7b6a55")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ReversibleAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testCalendarEventCreatedCodableRoundTrip() throws {
        let action = ReversibleAction.calendarEventCreated(id: "evt_abc123XYZ")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ReversibleAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    /// The id survives the round-trip even when it contains URL-unfriendly bytes,
    /// proving the associated value is encoded verbatim (not pre-escaped).
    func testNewCasesPreserveIdsWithUnusualCharacters() throws {
        let weird = "id/with+odd=chars and spaces"
        for action: ReversibleAction in [.gmailDraftCreated(id: weird),
                                         .calendarEventCreated(id: weird)] {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(ReversibleAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    // MARK: - Labels (new cases)

    func testNewCaseLabels() {
        XCTAssertEqual(ReversibleAction.gmailDraftCreated(id: "x").label,
                       "creating the Gmail draft")
        XCTAssertEqual(ReversibleAction.calendarEventCreated(id: "x").label,
                       "adding the calendar event")
    }

    // MARK: - Pure DELETE-URL builders

    func testDraftDeleteURL() {
        let url = GoogleConnector.draftDeleteURL(id: "r12345")
        XCTAssertEqual(url.absoluteString,
                       "https://gmail.googleapis.com/gmail/v1/users/me/drafts/r12345")
    }

    func testEventDeleteURL() {
        let url = GoogleConnector.eventDeleteURL(id: "evt67890")
        XCTAssertEqual(url.absoluteString,
                       "https://www.googleapis.com/calendar/v3/calendars/primary/events/evt67890")
    }

    /// An id with path-unsafe characters is percent-encoded so the URL stays
    /// well-formed (never nil-crashes the force-unwrap).
    func testDeleteURLsPercentEncodeUnsafeIds() {
        let draft = GoogleConnector.draftDeleteURL(id: "a b/c")
        XCTAssertTrue(draft.absoluteString.hasSuffix("/drafts/a%20b/c"))
        let event = GoogleConnector.eventDeleteURL(id: "a b")
        XCTAssertTrue(event.absoluteString.hasSuffix("/events/a%20b"))
    }

    // MARK: - Revert with no token → clean failure (no network)

    func testRevertGmailDraftWithNoTokenFailsCleanly() async {
        let result = await UndoStack.revert(.gmailDraftCreated(id: "r1"),
                                            googleToken: { nil })
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("reconnect google"),
                      "expected a reconnect-Google hint, got: \(result.output)")
    }

    func testRevertCalendarEventWithNoTokenFailsCleanly() async {
        let result = await UndoStack.revert(.calendarEventCreated(id: "e1"),
                                            googleToken: { nil })
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("reconnect google"),
                      "expected a reconnect-Google hint, got: \(result.output)")
    }
}
