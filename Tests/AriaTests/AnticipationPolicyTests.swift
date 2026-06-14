import XCTest
@testable import Aria

final class AnticipationPolicyTests: XCTestCase {
    private func sug(_ action: SuggestionAction, _ confidence: Double) -> Suggestion {
        Suggestion(source: .routine, spokenLine: "x", action: action, confidence: confidence,
                   urgency: .ambient, createdAt: Date(), expiry: Date().addingTimeInterval(60),
                   dedupeKey: "k")
    }

    func testActsOnHighConfidenceReversibleCommand() {
        let cmd = AnticipationPolicy.autoActCommand(for: sug(.runCommand("open my standup doc"), 0.95), enabled: true)
        XCTAssertEqual(cmd, "open my standup doc")
    }
    func testDisabledNeverActs() {
        XCTAssertNil(AnticipationPolicy.autoActCommand(for: sug(.runCommand("open notes"), 0.99), enabled: false))
    }
    func testLowConfidenceDoesNotAct() {
        XCTAssertNil(AnticipationPolicy.autoActCommand(for: sug(.runCommand("open notes"), 0.7), enabled: true))
    }
    func testDestructiveCommandNeverAutoActs() {
        XCTAssertNil(AnticipationPolicy.autoActCommand(for: sug(.runCommand("delete the old backups"), 0.99), enabled: true))
        XCTAssertNil(AnticipationPolicy.autoActCommand(for: sug(.runCommand("send the report to Sara"), 0.99), enabled: true))
    }
    func testNonCommandActionDoesNotAct() {
        XCTAssertNil(AnticipationPolicy.autoActCommand(for: sug(.acknowledge, 0.99), enabled: true))
    }
}
