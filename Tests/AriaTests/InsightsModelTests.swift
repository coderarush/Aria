import XCTest
@testable import Aria

final class InsightsModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func pattern(_ desc: String, _ conf: Double, _ status: PatternStatus) -> BehaviorPattern {
        BehaviorPattern(description: desc,
                        trigger: .appLaunched(bundleId: "com.x"),
                        action: .askUser("do it"),
                        confidence: conf, occurrences: [], status: status)
    }

    func testRoutinesFilterLowConfidenceAndSuppressedThenSortDescending() {
        let rows = InsightsModel.learnedRoutineRows(from: [
            pattern("high", 0.9, .approved),
            pattern("low", 0.5, .observing),      // below floor
            pattern("mid", 0.8, .observing),
            pattern("dropped", 0.95, .suppressed),
        ])
        XCTAssertEqual(rows.map(\.summary), ["high", "mid"])   // low below floor, dropped suppressed
        XCTAssertEqual(rows.first?.confidenceLabel, "90%")
    }

    func testConfidencePercentClamps() {
        XCTAssertEqual(InsightsModel.confidencePercent(1.4), "100%")
        XCTAssertEqual(InsightsModel.confidencePercent(-0.2), "0%")
        XCTAssertEqual(InsightsModel.confidencePercent(0.866), "87%")
    }

    func testSourceAndTitleFromDedupeKey() {
        XCTAssertEqual(InsightsModel.source(forDedupeKey: "routine:abc"), .routine)
        XCTAssertEqual(InsightsModel.source(forDedupeKey: "downloads.pdf.x"), .downloads)
        XCTAssertNil(InsightsModel.source(forDedupeKey: "weird"))
        XCTAssertEqual(InsightsModel.title(forDedupeKey: "calendar:1"), "Meeting reminder")
        XCTAssertEqual(InsightsModel.title(forDedupeKey: "weird"), "Proactive nudge")
    }

    func testVerdictWelcomedVsBackedOff() {
        var welcomed = SuggestionFeedback(); welcomed.accepts = 2
        XCTAssertEqual(InsightsModel.verdict(for: welcomed, now: t0), .welcomed)

        var dismissed = SuggestionFeedback(); dismissed.dismisses = 2
        XCTAssertEqual(InsightsModel.verdict(for: dismissed, now: t0), .backedOff)
    }

    func testNudgeRowsSkipNoOutcomeAndAreNewestFirst() {
        var seen = SuggestionFeedback()              // no accepts/dismisses → skipped
        var a = SuggestionFeedback(); a.accepts = 1; a.lastDismiss = t0
        var b = SuggestionFeedback(); b.dismisses = 1; b.lastDismiss = t0.addingTimeInterval(100)
        var store = ProactiveStore()
        store = applyFeedback(store, ["seen:x": seen, "routine:a": a, "calendar:b": b])
        let rows = InsightsModel.nudgeRows(from: store, now: t0.addingTimeInterval(200))
        XCTAssertEqual(rows.count, 2)               // "seen:x" skipped
        XCTAssertEqual(rows.first?.id, "calendar:b") // most recent dismiss first
    }

    // ProactiveStore.feedback is private(set); rebuild it by recording outcomes.
    private func applyFeedback(_ store: ProactiveStore, _ map: [String: SuggestionFeedback]) -> ProactiveStore {
        var s = store
        for (key, fb) in map {
            for _ in 0..<fb.accepts { s.record(.accepted, key: key, now: t0) }
            for _ in 0..<fb.dismisses { s.record(.dismissed, key: key, now: fb.lastDismiss ?? t0) }
        }
        return s
    }
}
