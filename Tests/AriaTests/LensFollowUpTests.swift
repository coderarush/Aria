import XCTest
@testable import Aria

final class LensFollowUpTests: XCTestCase {
    private func cap(_ text: String, ageSeconds: TimeInterval = 0) -> LensCapture {
        LensCapture(text: text, at: Date(timeIntervalSinceReferenceDate: 1000 - ageSeconds))
    }
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    func testFoldsDeicticActionWithFreshCapture() {
        let folded = LensFollowUp.fold(command: "translate that to Spanish", capture: cap("Bonjour le monde"), now: now)
        XCTAssertNotNil(folded)
        XCTAssertTrue(folded!.contains("translate that to Spanish"))
        XCTAssertTrue(folded!.contains("Bonjour le monde"))
    }

    func testNoFoldWithoutDeictic() {
        XCTAssertNil(LensFollowUp.fold(command: "what is the weather", capture: cap("some text"), now: now))
    }

    func testNoFoldWhenStale() {
        XCTAssertNil(LensFollowUp.fold(command: "fix this", capture: cap("err", ageSeconds: 300), now: now))
    }

    func testNoFoldWithoutCapture() {
        XCTAssertNil(LensFollowUp.fold(command: "fix this", capture: nil, now: now))
    }

    func testWordBoundaryAvoidsFalsePositives() {
        // "item" contains "it" but isn't the pronoun → no fold.
        XCTAssertNil(LensFollowUp.fold(command: "add an item to the list", capture: cap("x"), now: now))
        XCTAssertFalse(LensFollowUp.containsWord("add an item", "it"))
        XCTAssertTrue(LensFollowUp.containsWord("fix it now", "it"))
    }
}
