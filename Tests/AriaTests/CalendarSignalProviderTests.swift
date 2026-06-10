import XCTest
@testable import Aria

final class CalendarSignalProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func provider(_ events: [UpcomingEvent]) -> CalendarSignalProvider {
        CalendarSignalProvider(leadWindow: 300) { _ in events }
    }

    func testEmitsSuggestionWithinLeadWindow() async {
        let evt = UpcomingEvent(id: "e1", title: "Standup", start: now.addingTimeInterval(240))
        let out = await provider([evt]).candidates(now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .calendar)
        XCTAssertEqual(out[0].urgency, .timeCritical)
        XCTAssertEqual(out[0].dedupeKey, "calendar:e1")
        XCTAssertTrue(out[0].spokenLine.contains("Standup"))
        XCTAssertTrue(out[0].spokenLine.contains("4 minutes"))
    }

    func testIgnoresEventsOutsideLeadWindow() async {
        let soon = UpcomingEvent(id: "e1", title: "Soon", start: now.addingTimeInterval(240))
        let far = UpcomingEvent(id: "e2", title: "Far", start: now.addingTimeInterval(3600))
        let past = UpcomingEvent(id: "e3", title: "Past", start: now.addingTimeInterval(-60))
        let out = await provider([soon, far, past]).candidates(now: now)
        XCTAssertEqual(out.map(\.dedupeKey), ["calendar:e1"])
    }

    func testSingularMinute() async {
        let evt = UpcomingEvent(id: "e1", title: "Sync", start: now.addingTimeInterval(40))
        let out = await provider([evt]).candidates(now: now)
        XCTAssertTrue(out[0].spokenLine.contains("1 minute."), out[0].spokenLine)
    }
}
