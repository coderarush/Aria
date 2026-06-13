import XCTest
@testable import Aria

/// Tests for the pure view-model logic behind the full Aria app window (v1):
/// conversation-row preparation, snippeting, relative-time formatting, and the
/// connector scaffold. No SwiftUI, no disk, no actors.
final class AppWindowTests: XCTestCase {

    // MARK: conversationRows

    private func turn(_ said: String, _ reply: String, _ ts: Date) -> ConversationTurn {
        ConversationTurn(timestamp: ts, transcript: said,
                         responseMessage: reply, responseType: .answer)
    }

    func testConversationRowsSortMostRecentFirst() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t2 = Date(timeIntervalSince1970: 3_000)
        let rows = AppWindowModel.conversationRows(from: [
            turn("oldest", "a", t0),
            turn("newest", "c", t2),
            turn("middle", "b", t1),
        ])
        XCTAssertEqual(rows.map(\.transcript), ["newest", "middle", "oldest"])
        XCTAssertEqual(rows.first?.date, t2)
    }

    func testConversationRowSnippetFallsBackToReplyWhenTranscriptEmpty() {
        let rows = AppWindowModel.conversationRows(from: [
            turn("   ", "Aria offered a summary", Date())
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].transcript, "")
        XCTAssertEqual(rows[0].snippet, "Aria offered a summary")
        XCTAssertEqual(rows[0].response, "Aria offered a summary")
    }

    func testConversationRowPreservesTurnIdentity() {
        let id = UUID()
        let t = ConversationTurn(id: id, timestamp: Date(), transcript: "hi",
                                 responseMessage: "hello", responseType: .answer)
        let rows = AppWindowModel.conversationRows(from: [t])
        XCTAssertEqual(rows.first?.id, id)
    }

    // MARK: snippet

    func testSnippetCollapsesNewlinesAndCaps() {
        XCTAssertEqual(AppWindowModel.snippet("a\nb\nc"), "a b c")
        let long = String(repeating: "x", count: 200)
        let s = AppWindowModel.snippet(long, max: 80)
        XCTAssertEqual(s.count, 81)               // 80 chars + ellipsis
        XCTAssertTrue(s.hasSuffix("\u{2026}"))
    }

    func testSnippetEmptyBecomesUntitled() {
        XCTAssertEqual(AppWindowModel.snippet("   \n  "), "Untitled")
    }

    // MARK: relativeTime

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func ago(_ seconds: TimeInterval) -> String {
            AppWindowModel.relativeTime(now.addingTimeInterval(-seconds), reference: now)
        }
        XCTAssertEqual(ago(5), "just now")
        XCTAssertEqual(ago(120), "2m ago")
        XCTAssertEqual(ago(3 * 3600), "3h ago")
        XCTAssertEqual(ago(2 * 86_400), "2d ago")
    }

    func testRelativeTimeFutureClampsToJustNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future = now.addingTimeInterval(500)
        XCTAssertEqual(AppWindowModel.relativeTime(future, reference: now), "just now")
    }

    func testRelativeTimeOldFallsBackToDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-30 * 86_400)   // 30 days → absolute date
        let result = AppWindowModel.relativeTime(old, reference: now)
        XCTAssertFalse(result.hasSuffix("ago"))
        XCTAssertNotEqual(result, "just now")
    }

    // MARK: connectors scaffold

    func testConnectorsAreAllPlaceholdersInV1() {
        XCTAssertFalse(AppWindowModel.connectors.isEmpty)
        XCTAssertTrue(AppWindowModel.connectors.allSatisfy { !$0.available },
                      "v1 connectors must all be disabled placeholders — no OAuth yet")
    }

    func testConnectorIDsAreUnique() {
        let ids = AppWindowModel.connectors.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testConnectorCatalogContainsExpectedIntegrations() {
        let names = Set(AppWindowModel.connectors.map(\.name))
        for expected in ["Gmail", "Google Calendar", "Notion", "Slack", "Apple Mail", "iCloud"] {
            XCTAssertTrue(names.contains(expected), "missing connector: \(expected)")
        }
    }
}
