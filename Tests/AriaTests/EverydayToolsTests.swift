import XCTest
import Contacts
@testable import Aria

final class TimerCenterTests: XCTestCase {

    func testParseDurationVariants() {
        XCTAssertEqual(TimerCenter.parseDuration("10 minutes"), 600)
        XCTAssertEqual(TimerCenter.parseDuration("90 sec"), 90)
        XCTAssertEqual(TimerCenter.parseDuration("1.5 hours"), 5400)
        XCTAssertEqual(TimerCenter.parseDuration("2:30"), 150)
        XCTAssertEqual(TimerCenter.parseDuration("45"), 45 * 60)   // bare number = minutes
        XCTAssertNil(TimerCenter.parseDuration("banana"))
        XCTAssertNil(TimerCenter.parseDuration(""))
        XCTAssertNil(TimerCenter.parseDuration("0 min"))
    }

    func testFormat() {
        XCTAssertEqual(TimerCenter.format(45), "45s")
        XCTAssertEqual(TimerCenter.format(120), "2m")
        XCTAssertEqual(TimerCenter.format(150), "2m 30s")
        XCTAssertEqual(TimerCenter.format(3600), "1h")
        XCTAssertEqual(TimerCenter.format(3900), "1h 5m")
    }

    func testTimerFiresAndRemovesItself() async {
        let fired = expectation(description: "timer fired")
        let center = TimerCenter(onFire: { label in
            XCTAssertEqual(label, "test")
            fired.fulfill()
        })
        await center.start(seconds: 0.05, label: "test")
        let midCount = await center.count
        XCTAssertEqual(midCount, 1)
        await fulfillment(of: [fired], timeout: 2)
        // Give the cleanup hop a beat.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let after = await center.count
        XCTAssertEqual(after, 0)
    }

    func testCancelByLabelAndAll() async {
        let center = TimerCenter(onFire: { _ in XCTFail("cancelled timers must not fire") })
        await center.start(seconds: 60, label: "pasta")
        await center.start(seconds: 60, label: "laundry")
        let cancelled = await center.cancel(matching: "pasta")
        XCTAssertEqual(cancelled, 1)
        let rest = await center.cancel(matching: nil)
        XCTAssertEqual(rest, 1)
        let count = await center.count
        XCTAssertEqual(count, 0)
    }

    func testListShowsRemaining() async {
        let center = TimerCenter(onFire: { _ in })
        let now = Date()
        await center.start(seconds: 300, label: "tea", now: now)
        let lines = await center.list(now: now)
        XCTAssertEqual(lines, ["tea — 5m left"])
        _ = await center.cancel(matching: nil)
    }
}

final class WeatherToolTests: XCTestCase {

    func testSummarizeFormatsForecast() throws {
        let json = """
        {"current": {"temperature_2m": 18.6, "apparent_temperature": 16.2,
                     "weather_code": 2, "wind_speed_10m": 14.3, "relative_humidity_2m": 62},
         "daily": {"temperature_2m_max": [21.4], "temperature_2m_min": [12.1],
                   "precipitation_probability_max": [35]}}
        """.data(using: .utf8)!
        let line = WeatherTool.summarize(place: "Cupertino, California", forecastJSON: json)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("Cupertino"))
        XCTAssertTrue(line!.contains("partly cloudy"))
        XCTAssertTrue(line!.contains("19°"))
        XCTAssertTrue(line!.contains("feels 16°"))
        XCTAssertTrue(line!.contains("12°–21°"))
        XCTAssertTrue(line!.contains("35% chance of rain"))
    }

    func testSummarizeRejectsGarbage() {
        XCTAssertNil(WeatherTool.summarize(place: "X", forecastJSON: Data("nope".utf8)))
        XCTAssertNil(WeatherTool.summarize(place: "X", forecastJSON: Data("{}".utf8)))
    }

    func testWeatherCodeWords() {
        XCTAssertEqual(WeatherTool.describe(code: 0), "clear")
        XCTAssertEqual(WeatherTool.describe(code: 63), "raining")
        XCTAssertEqual(WeatherTool.describe(code: 95), "thunderstorms")
        XCTAssertEqual(WeatherTool.describe(code: 999), "unsettled")
    }
}

final class SystemStatusToolTests: XCTestCase {

    func testParseBattery() {
        let discharging = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=1234)\t84%; discharging; 4:32 remaining present: true
        """
        XCTAssertEqual(SystemStatusTool.parseBattery(discharging), "Battery 84%, on battery.")
        let charging = " -InternalBattery-0\t51%; charging; 1:10 remaining"
        XCTAssertEqual(SystemStatusTool.parseBattery(charging), "Battery 51%, charging.")
        XCTAssertNil(SystemStatusTool.parseBattery("Now drawing from 'AC Power'\n"))
    }

    func testStatusToolProducesLines() async throws {
        let result = try await SystemStatusTool().run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Disk:"))
        XCTAssertTrue(result.output.contains("Uptime:"))
        XCTAssertTrue(result.output.contains("Thermals:"))
    }
}

final class WindowGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    func testHalvesAndCorners() {
        XCTAssertEqual(WindowGeometry.frame(for: .left, in: screen),
                       CGRect(x: 0, y: 0, width: 800, height: 900))
        XCTAssertEqual(WindowGeometry.frame(for: .right, in: screen),
                       CGRect(x: 800, y: 0, width: 800, height: 900))
        XCTAssertEqual(WindowGeometry.frame(for: .topRight, in: screen),
                       CGRect(x: 800, y: 450, width: 800, height: 450))
        XCTAssertEqual(WindowGeometry.frame(for: .maximize, in: screen), screen)
    }

    func testCenterIsThreeQuartersCentered() {
        let center = WindowGeometry.frame(for: .center, in: screen)
        XCTAssertEqual(center.width, 1200)
        XCTAssertEqual(center.height, 675)
        XCTAssertEqual(center.midX, screen.midX)
        XCTAssertEqual(center.midY, screen.midY)
    }

    func testVisibleFrameOffsetRespected() {
        // Dock on the left + menu bar: visible frame is inset.
        let visible = CGRect(x: 70, y: 0, width: 1530, height: 875)
        let left = WindowGeometry.frame(for: .left, in: visible)
        XCTAssertEqual(left.minX, 70)
        XCTAssertEqual(left.width, 765)
    }

    func testAXConversionFlipsY() {
        // A top-half frame in Cocoa coords must land at the top in AX coords.
        let top = WindowGeometry.frame(for: .top, in: screen)
        let ax = WindowGeometry.axPosition(for: top, primaryHeight: 900)
        XCTAssertEqual(ax.y, 0)
        let bottom = WindowGeometry.frame(for: .bottom, in: screen)
        let axBottom = WindowGeometry.axPosition(for: bottom, primaryHeight: 900)
        XCTAssertEqual(axBottom.y, 450)
    }

    func testPositionParsing() {
        XCTAssertEqual(WindowGeometry.Position.parse("left half"), .left)
        XCTAssertEqual(WindowGeometry.Position.parse("Top Right"), .topRight)
        XCTAssertEqual(WindowGeometry.Position.parse("fullscreen"), .maximize)
        XCTAssertEqual(WindowGeometry.Position.parse("middle"), .center)
        XCTAssertNil(WindowGeometry.Position.parse("sideways"))
    }
}

final class ContactsToolFormatTests: XCTestCase {

    func testCardFormatsNamePhonesEmailsBirthday() {
        let contact = CNMutableContact()
        contact.givenName = "Sam"
        contact.familyName = "Rivera"
        contact.organizationName = "Acme"
        contact.phoneNumbers = [CNLabeledValue(
            label: CNLabelPhoneNumberMobile,
            value: CNPhoneNumber(stringValue: "555-0100"))]
        contact.emailAddresses = [CNLabeledValue(
            label: CNLabelWork, value: "sam@acme.com" as NSString)]
        var birthday = DateComponents()
        birthday.month = 3; birthday.day = 14
        contact.birthday = birthday

        let card = ContactsTool.card(for: contact)
        XCTAssertTrue(card.contains("Sam Rivera (Acme)"))
        XCTAssertTrue(card.contains("555-0100"))
        XCTAssertTrue(card.contains("sam@acme.com"))
        XCTAssertTrue(card.contains("birthday: March 14"))
    }

    func testMissingNameToolInputFails() async throws {
        let result = try await ContactsTool().run(input: [:])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.hasPrefix("Missing input"))
    }
}

final class MusicToolInputTests: XCTestCase {

    func testUnknownActionFailsCleanly() async throws {
        let result = try await MusicTool().run(input: ["action": "yeet"])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("Unknown action"))
    }
}
