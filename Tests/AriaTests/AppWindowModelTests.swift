import XCTest
@testable import Aria

/// Pure-logic tests for the main window's view-model. The view itself is SwiftUI
/// chrome; the testable surface is the filtering / grouping / formatting helpers.
@MainActor
final class AppWindowModelTests: XCTestCase {

    private func row(_ transcript: String, _ response: String,
                     at date: Date = Date()) -> ConversationRow {
        ConversationRow(id: UUID(), timestamp: date, transcript: transcript, response: response)
    }

    // MARK: filterConversations

    func testFilterEmptyQueryReturnsAll() {
        let rows = [row("hello", "hi"), row("weather", "sunny")]
        XCTAssertEqual(AppWindowModel.filterConversations(rows, query: "   ").count, 2)
        XCTAssertEqual(AppWindowModel.filterConversations(rows, query: "").count, 2)
    }

    func testFilterMatchesTranscriptAndResponseCaseInsensitively() {
        let rows = [row("Email Sarah", "Done, sent."),
                    row("What's the weather", "It's Sunny today")]
        XCTAssertEqual(AppWindowModel.filterConversations(rows, query: "EMAIL").count, 1)
        XCTAssertEqual(AppWindowModel.filterConversations(rows, query: "sunny").count, 1)   // matches response
        XCTAssertEqual(AppWindowModel.filterConversations(rows, query: "zzz").count, 0)
    }

    // MARK: groupByDay

    func testGroupByDaySplitsAndSortsNewestFirst() {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let entries = [
            ActivityEntry(date: yesterday, tool: "a", detail: "", outcome: .ok, summary: ""),
            ActivityEntry(date: today, tool: "b", detail: "", outcome: .ok, summary: ""),
            ActivityEntry(date: today.addingTimeInterval(-60), tool: "c", detail: "", outcome: .ok, summary: ""),
        ]
        let groups = AppWindowModel.groupByDay(entries, calendar: cal)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.entries.count, 2)               // today's two entries
        XCTAssertEqual(groups.first?.entries.first?.tool, "b")        // newest within the day first
        XCTAssertTrue(groups.first!.day > groups.last!.day)          // newest day first
    }

    func testGroupByDayEmpty() {
        XCTAssertTrue(AppWindowModel.groupByDay([]).isEmpty)
    }

    // MARK: dayLabel

    func testDayLabelTodayYesterday() {
        let cal = Calendar.current
        XCTAssertEqual(AppWindowModel.dayLabel(Date(), calendar: cal), "Today")
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(AppWindowModel.dayLabel(yesterday, calendar: cal), "Yesterday")
        let old = cal.date(byAdding: .day, value: -10, to: Date())!
        XCTAssertNotEqual(AppWindowModel.dayLabel(old, calendar: cal), "Today")
        XCTAssertFalse(AppWindowModel.dayLabel(old, calendar: cal).isEmpty)
    }

    // MARK: relativeTime

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-90_000), now: now), "yesterday")
        XCTAssertEqual(AppWindowModel.relativeTime(now.addingTimeInterval(-259_200), now: now), "3d ago")
    }

    // MARK: oneLine

    func testOneLineCollapsesAndCaps() {
        XCTAssertEqual(AppWindowModel.oneLine("  a\nb\nc  "), "a b c")
        let long = String(repeating: "x", count: 200)
        let capped = AppWindowModel.oneLine(long, max: 50)
        XCTAssertEqual(capped.count, 51)         // 50 + ellipsis
        XCTAssertTrue(capped.hasSuffix("…"))
    }

    // MARK: greeting

    func testGreetingByHour() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(AppWindowModel.greeting(now: at(8), calendar: cal), "Good morning")
        XCTAssertEqual(AppWindowModel.greeting(now: at(14), calendar: cal), "Good afternoon")
        XCTAssertEqual(AppWindowModel.greeting(now: at(19), calendar: cal), "Good evening")
        XCTAssertEqual(AppWindowModel.greeting(now: at(2), calendar: cal), "Still up")
    }

    // MARK: ConversationRow derived fields

    func testConversationRowTitleAndSnippet() {
        let blank = row("   ", "ok")
        XCTAssertEqual(blank.title, "Voice request")
        let r = row("Book a table", "Reserved for 7pm.\nConfirmation sent.")
        XCTAssertEqual(r.title, "Book a table")
        XCTAssertFalse(r.snippet.contains("\n"))
    }

    // MARK: connectors catalog

    func testConnectorCatalogIsAllComingSoonAndUnique() {
        let cat = AppWindowModel.connectorCatalog
        XCTAssertEqual(cat.count, 6)
        XCTAssertEqual(Set(cat.map(\.id)).count, cat.count, "connector ids are unique")
        XCTAssertTrue(cat.allSatisfy { $0.status == .comingSoon })
        XCTAssertTrue(cat.contains { $0.name == "Gmail" })
        XCTAssertTrue(cat.contains { $0.name == "Notion" })
        XCTAssertTrue(cat.allSatisfy { !$0.icon.isEmpty })
    }

    // MARK: section metadata

    func testSectionsHaveIconsAndIds() {
        for s in AppSection.allCases {
            XCTAssertFalse(s.icon.isEmpty)
            XCTAssertEqual(s.id, s.rawValue)
        }
        XCTAssertEqual(AppSection.allCases.count, 5)
    }
}
