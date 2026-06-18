import XCTest
@testable import Aria

final class IntentEngineTests: XCTestCase {

    private func world(activeApp: String) -> CurrentWorldState {
        CurrentWorldState.build(activeApp: activeApp, focusSince: Date(), clipboardSummary: nil,
                                openFiles: [], recentActions: [], pendingSuggestion: nil, now: Date())
    }

    func testFiltersBelowConfidenceFloor() {
        let candidates = [
            PredictedIntent(action: "run tests", confidence: 0.8, reasoning: "tests not run"),
            PredictedIntent(action: "tidy desktop", confidence: 0.3, reasoning: "many files"),
        ]
        let ranked = IntentEngine.rank(candidates, world: world(activeApp: "Finder"), floor: 0.55)
        XCTAssertEqual(ranked.map(\.action), ["run tests"])
    }

    func testActiveAppContextBoostsReordering() {
        // Lower base confidence, but the intent is about the app in focus → it wins.
        let candidates = [
            PredictedIntent(action: "draft reply", confidence: 0.70, reasoning: "copied text in Safari"),
            PredictedIntent(action: "run tests in Xcode", confidence: 0.62, reasoning: "tests stale"),
        ]
        let ranked = IntentEngine.rank(candidates, world: world(activeApp: "Xcode"), floor: 0.5)
        XCTAssertEqual(ranked.first?.action, "run tests in Xcode", "the in-focus intent should be boosted above")
    }

    func testNoBoostKeepsConfidenceOrder() {
        let candidates = [
            PredictedIntent(action: "a", confidence: 0.6, reasoning: "x"),
            PredictedIntent(action: "b", confidence: 0.9, reasoning: "y"),
        ]
        let ranked = IntentEngine.rank(candidates, world: world(activeApp: "Mail"), floor: 0.5)
        XCTAssertEqual(ranked.map(\.action), ["b", "a"])
    }

    func testBoostNeverExceedsOne() {
        let c = [PredictedIntent(action: "open Xcode", confidence: 0.98, reasoning: "Xcode")]
        let ranked = IntentEngine.rank(c, world: world(activeApp: "Xcode"), floor: 0.5)
        XCTAssertLessThanOrEqual(ranked.first!.confidence, 1.0)
    }

    func testBoostedConfidencePrimitive() {
        XCTAssertEqual(IntentEngine.boostedConfidence(text: "run tests in Xcode", base: 0.6, activeApp: "Xcode"),
                       0.75, accuracy: 0.001)
        XCTAssertEqual(IntentEngine.boostedConfidence(text: "draft reply", base: 0.6, activeApp: "Xcode"),
                       0.6, accuracy: 0.001)           // no mention → unchanged
        XCTAssertEqual(IntentEngine.boostedConfidence(text: "anything", base: 0.6, activeApp: ""),
                       0.6, accuracy: 0.001)           // no focus → unchanged
    }
}
