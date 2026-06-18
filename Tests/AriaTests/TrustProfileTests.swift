import XCTest
@testable import Aria

final class TrustProfileTests: XCTestCase {

    func testImportantIrreversibleAsksWhenConfirmOn() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .importantIrreversible, confirmsDestructive: true),
            .ask)
    }

    func testImportantIrreversibleAutosWhenUserOptedOut() {
        // Power-user zero-friction override — still receipted + undoable.
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .importantIrreversible, confirmsDestructive: false),
            .auto)
    }

    func testRoutineAlwaysAuto() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .routine, confirmsDestructive: true),
            .auto)
    }

    func testHealthyReversibleAutos() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .reversible, confirmsDestructive: true,
                                      patternSuccessRatio: 0.9, samplesMet: true),
            .auto)
    }

    func testFailingReversibleDropsToSuggest() {
        // A reversible automation that keeps failing should stop auto-firing.
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .reversible, confirmsDestructive: true,
                                      patternSuccessRatio: 0.2, samplesMet: true),
            .suggest)
    }

    func testFailingReversibleBelowSampleThresholdStaysAuto() {
        // Not enough samples yet → stay optimistic.
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .reversible, confirmsDestructive: true,
                                      patternSuccessRatio: 0.2, samplesMet: false),
            .auto)
    }
}
