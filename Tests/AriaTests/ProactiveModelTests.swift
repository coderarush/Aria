import XCTest
@testable import Aria

final class ProactiveModelTests: XCTestCase {

    private func make(expiry: Date, urgency: Urgency = .ambient) -> Suggestion {
        Suggestion(source: .calendar,
                   spokenLine: "Standup starts in 5 minutes.",
                   action: .acknowledge,
                   confidence: 0.9,
                   urgency: urgency,
                   createdAt: Date(timeIntervalSince1970: 0),
                   expiry: expiry,
                   dedupeKey: "calendar:evt-1")
    }

    func testIsExpiredWhenNowPastExpiry() {
        let s = make(expiry: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(s.isExpired(now: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(s.isExpired(now: Date(timeIntervalSince1970: 101)))
    }

    func testRankSortsTimeCriticalBeforeAmbientThenConfidence() {
        let ambientHigh = make(expiry: Date(timeIntervalSince1970: 100), urgency: .ambient)
        let critical = make(expiry: Date(timeIntervalSince1970: 100), urgency: .timeCritical)
        // time-critical outranks a higher-confidence ambient one
        XCTAssertTrue(Suggestion.rank(critical, before: ambientHigh))
        XCTAssertFalse(Suggestion.rank(ambientHigh, before: critical))
    }

    func testRankBreaksTieByConfidence() {
        var a = make(expiry: Date(timeIntervalSince1970: 100))
        var b = make(expiry: Date(timeIntervalSince1970: 100))
        a.confidence = 0.9
        b.confidence = 0.6
        XCTAssertTrue(Suggestion.rank(a, before: b))
    }
}
