import XCTest
@testable import Aria

final class ReasoningPanelTests: XCTestCase {

    private func intent(_ action: String, _ conf: Double, _ reason: String) -> PredictedIntent {
        PredictedIntent(action: action, confidence: conf, reasoning: reason)
    }

    func testExplainPicksTopIntent() {
        let r = ReasoningPanel.explain([
            intent("archive inbox", 0.9, "Inbox is full and it's morning."),
            intent("draft reply", 0.6, "A thread is waiting.")
        ], floor: 0)
        XCTAssertEqual(r?.confidence, 0.9)
        XCTAssertTrue(r?.why.contains("Inbox") ?? false)
    }

    func testAlternativesAreRunnersUp() {
        let r = ReasoningPanel.explain([
            intent("a", 0.9, "x"), intent("b", 0.7, "y"), intent("c", 0.5, "z")
        ], floor: 0)
        XCTAssertEqual(r?.alternatives, ["b", "c"])
    }

    func testConcisesReasoningNoChainOfThought() {
        let verbose = "First I considered the inbox. Then I weighed the calendar. Therefore archive."
        let r = ReasoningPanel.explain([intent("archive", 0.8, verbose)], floor: 0)
        XCTAssertFalse(r?.why.contains("Then I weighed") ?? true)   // single concise line only
        XCTAssertLessThan(r?.why.count ?? 999, 165)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(ReasoningPanel.explain([], floor: 0))
    }

    func testWorldRankingBoostsActiveApp() {
        let world = CurrentWorldState.build(activeApp: "Xcode", focusSince: nil,
                                            clipboardSummary: nil, openFiles: [], recentActions: [],
                                            pendingSuggestion: nil, now: Date(timeIntervalSince1970: 1))
        let r = ReasoningPanel.explain([
            intent("open Mail", 0.6, "mail waiting"),
            intent("build in Xcode", 0.6, "compile the Xcode project")
        ], world: world, floor: 0.5)
        XCTAssertEqual(r?.why.lowercased().contains("xcode"), true)   // active-app intent wins
    }
}
