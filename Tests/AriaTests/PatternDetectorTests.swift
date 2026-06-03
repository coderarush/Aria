import XCTest
@testable import Aria

final class PatternDetectorTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Build a date at a given weekday-ish offset and time.
    private func date(dayOffset: Int, hour: Int, minute: Int) -> Date {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 1; comp.day = 5 + dayOffset  // Jan 5 2026 = Monday
        comp.hour = hour; comp.minute = minute
        return cal.date(from: comp)!
    }

    func testDetectsConsistentMorningCommand() {
        // "git pull" every day at ~09:00 for 6 days.
        var events: [CommandEvent] = []
        for d in 0..<6 {
            events.append(CommandEvent(command: "git pull", timestamp: date(dayOffset: d, hour: 9, minute: d * 3)))
        }
        let patterns = PatternDetector.detectTimePatterns(commands: events, sensitivity: 0.7, calendar: cal)
        XCTAssertEqual(patterns.count, 1)
        if case let .timeOfDay(hour, _, _) = patterns[0].trigger {
            XCTAssertEqual(hour, 9)
        } else { XCTFail("expected timeOfDay trigger") }
        XCTAssertGreaterThanOrEqual(patterns[0].confidence, 0.7)
    }

    func testIgnoresBelowMinOccurrences() {
        let events = (0..<4).map { CommandEvent(command: "rare task", timestamp: date(dayOffset: $0, hour: 8, minute: 0)) }
        let patterns = PatternDetector.detectTimePatterns(commands: events, sensitivity: 0.7, calendar: cal)
        XCTAssertTrue(patterns.isEmpty)
    }

    func testIgnoresInconsistentTimes() {
        // 5 occurrences scattered across the day — low consistency.
        let hours = [6, 11, 14, 19, 22]
        let events = hours.enumerated().map {
            CommandEvent(command: "scattered", timestamp: date(dayOffset: $0.offset, hour: $0.element, minute: 0))
        }
        let patterns = PatternDetector.detectTimePatterns(commands: events, sensitivity: 0.7, calendar: cal)
        XCTAssertTrue(patterns.isEmpty)
    }

    func testSensitivityGate() {
        // 5 in-window + nothing else = consistency 1.0; but high sensitivity still passes.
        let events = (0..<5).map { CommandEvent(command: "task", timestamp: date(dayOffset: $0, hour: 10, minute: 5)) }
        let conservative = PatternDetector.detectTimePatterns(commands: events, sensitivity: 0.9, calendar: cal)
        XCTAssertEqual(conservative.count, 1)
    }

    func testCircularMeanWrapsMidnight() {
        // 23:50 and 00:10 should average to ~00:00, not 12:00.
        let mean = PatternDetector.circularMeanMinute([1430, 10]) ?? -1
        XCTAssertTrue(mean <= 5 || mean >= 1435, "got \(mean)")
    }

    func testAngularDistanceWraps() {
        XCTAssertEqual(PatternDetector.angularDistance(1430, 10), 20)
        XCTAssertEqual(PatternDetector.angularDistance(540, 600), 60)
    }

    func testTriggerMatchesWithinWindow() {
        let trigger = PatternTrigger.timeOfDay(hour: 9, minute: 0, days: [])
        XCTAssertTrue(PatternDetector.triggerMatches(trigger, now: date(dayOffset: 0, hour: 9, minute: 20), calendar: cal))
        XCTAssertFalse(PatternDetector.triggerMatches(trigger, now: date(dayOffset: 0, hour: 11, minute: 0), calendar: cal))
    }

    func testExpiry() {
        let old = BehaviorPattern(
            description: "x", trigger: .timeOfDay(hour: 9, minute: 0, days: []),
            action: .runSavedCommand("x"), confidence: 0.9,
            occurrences: [Date(timeIntervalSinceNow: -40 * 24 * 3600)])
        XCTAssertTrue(PatternDetector.isExpired(old))
        let fresh = BehaviorPattern(
            description: "y", trigger: .timeOfDay(hour: 9, minute: 0, days: []),
            action: .runSavedCommand("y"), confidence: 0.9, occurrences: [Date()])
        XCTAssertFalse(PatternDetector.isExpired(fresh))
    }
}
