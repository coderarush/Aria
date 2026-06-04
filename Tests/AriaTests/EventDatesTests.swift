import XCTest
@testable import Aria

final class EventDatesTests: XCTestCase {
    func testParsesISO8601() {
        XCTAssertNotNil(EventDates.parse("2026-06-10T15:00:00Z"))
        XCTAssertNotNil(EventDates.parse("2026-06-10T15:00:00.000Z"))
    }
    func testParsesPlainFormats() {
        XCTAssertNotNil(EventDates.parse("2026-06-10 15:00"))
        XCTAssertNotNil(EventDates.parse("2026-06-10T15:00"))
        XCTAssertNotNil(EventDates.parse("2026-06-10"))
    }
    func testRejectsGarbageAndEmpty() {
        XCTAssertNil(EventDates.parse("not a date"))
        XCTAssertNil(EventDates.parse(""))
        XCTAssertNil(EventDates.parse(nil))
    }
}
