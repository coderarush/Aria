import XCTest
@testable import Aria

final class ProactiveSettingsTests: XCTestCase {

    private func cal(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 9; c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    func testQuietHoursSameDayRange() {
        let q = QuietHours(startHour: 9, endHour: 17)
        XCTAssertTrue(q.contains(cal(hour: 12)))
        XCTAssertFalse(q.contains(cal(hour: 8)))
        XCTAssertFalse(q.contains(cal(hour: 17)))   // end is exclusive
    }

    func testQuietHoursOvernightWrap() {
        let q = QuietHours(startHour: 22, endHour: 7)
        XCTAssertTrue(q.contains(cal(hour: 23)))
        XCTAssertTrue(q.contains(cal(hour: 2)))
        XCTAssertFalse(q.contains(cal(hour: 12)))
    }

    func testSettingsDefaults() {
        let d = UserDefaults(suiteName: "proactive-defaults-\(UUID().uuidString)")!
        let s = ProactiveSettings.load(d)
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.isSourceEnabled(.calendar))
        XCTAssertTrue(s.isSourceEnabled(.routine))
        XCTAssertFalse(s.isSourceEnabled(.screen))   // privacy: off by default
    }

    func testSettingsRoundTrip() {
        let d = UserDefaults(suiteName: "proactive-rt-\(UUID().uuidString)")!
        var s = ProactiveSettings.load(d)
        s.enabled = false
        s.sourceEnabled[.calendar] = false
        s.quietHoursEnabled = true
        s.save(d)
        let reloaded = ProactiveSettings.load(d)
        XCTAssertFalse(reloaded.enabled)
        XCTAssertFalse(reloaded.isSourceEnabled(.calendar))
        XCTAssertTrue(reloaded.quietHoursEnabled)
    }
}
