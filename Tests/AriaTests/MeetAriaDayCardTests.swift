import XCTest
@testable import Aria

/// Tests the pure "here's your day" formatter behind the Meet Aria onboarding
/// moment. No EventKit, no filesystem — all data is injected, so these are fast
/// and deterministic (a fixed UTC calendar + reference dates).
final class MeetAriaDayCardTests: XCTestCase {

    /// A stable calendar so date/time formatting is reproducible across machines.
    private func utcCal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2024-06-14 09:30 UTC (a Friday) — used as "now" anchor for most cases.
    private func anchor() -> Date { Date(timeIntervalSince1970: 1_718_357_400) }

    // MARK: greeting

    func testGreetingBuckets() {
        let cal = utcCal()
        func at(_ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: anchor())!
        }
        XCTAssertEqual(DayCard.greeting(for: at(8), calendar: cal), "Good morning.")
        XCTAssertEqual(DayCard.greeting(for: at(14), calendar: cal), "Good afternoon.")
        XCTAssertEqual(DayCard.greeting(for: at(19), calendar: cal), "Good evening.")
        XCTAssertEqual(DayCard.greeting(for: at(3), calendar: cal), "Hello.")
    }

    // MARK: cleanTitle — never blank

    func testCleanTitleReplacesEmptyAndTrims() {
        XCTAssertEqual(DayCard.cleanTitle("  Investor sync  "), "Investor sync")
        XCTAssertEqual(DayCard.cleanTitle("   "), "Untitled event")
        XCTAssertEqual(DayCard.cleanTitle(""), "Untitled event")
    }

    // MARK: make — events sorted, capped, all-day filtered

    func testEventsSortedTrimmedCappedAndAllDayFiltered() {
        let cal = utcCal()
        let base = anchor()
        let raw: [(start: Date, title: String, allDay: Bool)] = [
            (base.addingTimeInterval(7200), "Later meeting", false),
            (base.addingTimeInterval(1800), "  Earlier call  ", false),
            (base, "All-day offsite", true),                 // filtered out
            (base.addingTimeInterval(3600), "Mid review", false),
            (base.addingTimeInterval(5400), "Fourth", false),
            (base.addingTimeInterval(9000), "Fifth (dropped)", false) // over cap of 4
        ]
        let card = DayCard.make(now: base, calendarAuthorized: true,
                                rawEvents: raw, rawFiles: [], calendar: cal)

        XCTAssertEqual(card.events.count, 4, "all-day filtered, capped at 4")
        XCTAssertEqual(card.events.map(\.title),
                       ["Earlier call", "Mid review", "Fourth", "Later meeting"],
                       "sorted by start time, titles trimmed")
        XCTAssertFalse(card.events.contains { $0.title == "All-day offsite" })
        XCTAssertFalse(card.events.contains { $0.title.contains("dropped") })
    }

    func testFilesCappedAtThreeInOrder() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: true,
                                rawEvents: [],
                                rawFiles: [("a.pdf", "Downloads"), ("b.png", "Desktop"),
                                           ("c.txt", "Downloads"), ("d.zip", "Desktop")],
                                calendar: utcCal())
        XCTAssertEqual(card.files.count, 3, "capped at 3")
        XCTAssertEqual(card.files.map(\.name), ["a.pdf", "b.png", "c.txt"])
        XCTAssertEqual(card.files.first?.where_, "Downloads")
    }

    // MARK: degradation — calendar not granted

    func testCalendarNudgeWhenNotAuthorized() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: false,
                                rawEvents: [], rawFiles: [("notes.md", "Desktop")],
                                calendar: utcCal())
        XCTAssertTrue(card.calendarNudge, "no calendar access → nudge flagged")
        XCTAssertFalse(card.hasEvents)
        XCTAssertTrue(card.hasFiles, "still shows recent files")
    }

    func testNoNudgeWhenAuthorizedEvenWithEmptyCalendar() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: true,
                                rawEvents: [], rawFiles: [], calendar: utcCal())
        XCTAssertFalse(card.calendarNudge, "authorized but empty is a clear day, not a nudge")
    }

    // MARK: summaryLine (spoken-style, deterministic)

    func testSummaryLineCountsEventsAndFiles() {
        let cal = utcCal()
        let base = anchor()
        let twoEvents: [(start: Date, title: String, allDay: Bool)] = [
            (base, "One", false), (base.addingTimeInterval(60), "Two", false)
        ]
        let card = DayCard.make(now: base, calendarAuthorized: true,
                                rawEvents: twoEvents,
                                rawFiles: [("x.pdf", "Downloads"), ("y.txt", "Desktop"),
                                           ("z.png", "Downloads")],
                                calendar: cal)
        XCTAssertEqual(card.summaryLine, "You have 2 events today and 3 recent files.")
    }

    func testSummaryLineSingularGrammar() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: true,
                                rawEvents: [(anchor(), "Solo", false)],
                                rawFiles: [("only.pdf", "Downloads")],
                                calendar: utcCal())
        XCTAssertEqual(card.summaryLine, "You have 1 event today and 1 recent file.")
    }

    func testSummaryLineEmptyButAuthorizedMentionsClearCalendar() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: true,
                                rawEvents: [], rawFiles: [], calendar: utcCal())
        XCTAssertEqual(card.summaryLine, "You have a clear calendar.")
    }

    func testSummaryLineFilesOnlyWhenCalendarNotGranted() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: false,
                                rawEvents: [],
                                rawFiles: [("a.pdf", "Downloads"), ("b.pdf", "Desktop")],
                                calendar: utcCal())
        // No calendar mention (not authorized), just the files.
        XCTAssertEqual(card.summaryLine, "You have 2 recent files.")
    }

    func testSummaryLineFullyEmptyAndUnauthorizedHasGracefulFallback() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: false,
                                rawEvents: [], rawFiles: [], calendar: utcCal())
        XCTAssertEqual(card.summaryLine, "Here's a look at your day.",
                       "never blank, even with nothing and no permissions")
    }

    // MARK: date headline is present + non-empty

    func testDateHeadlineNonEmpty() {
        let card = DayCard.make(now: anchor(), calendarAuthorized: true,
                                rawEvents: [], rawFiles: [], calendar: utcCal())
        XCTAssertFalse(card.dateHeadline.isEmpty)
    }
}
