import XCTest
@testable import Aria

final class ContextCoordinatorTests: XCTestCase {

    func testBuildComputesFocusDurationAndConfidence() {
        let now = Date()
        let s = CurrentWorldState.build(
            activeApp: "Xcode",
            focusSince: now.addingTimeInterval(-120),
            clipboardSummary: "some copied text",
            openFiles: ["Notes.md"],
            recentActions: ["Sent email to Sara"],
            pendingSuggestion: nil,
            now: now)
        XCTAssertEqual(s.activeApp, "Xcode")
        XCTAssertEqual(s.focusDuration, 120, accuracy: 0.5)
        // 4 of 4 core signals present (app, clipboard, files, actions) → 1.0.
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.timestamp, now)
    }

    func testBuildEmptyWorldIsLowConfidence() {
        let now = Date()
        let s = CurrentWorldState.build(
            activeApp: "", focusSince: nil, clipboardSummary: nil,
            openFiles: [], recentActions: [], pendingSuggestion: nil, now: now)
        XCTAssertEqual(s.activeApp, "")
        XCTAssertEqual(s.focusDuration, 0, accuracy: 0.001)
        XCTAssertEqual(s.confidence, 0.0, accuracy: 0.001)
    }

    func testBuildPartialConfidence() {
        let now = Date()
        let s = CurrentWorldState.build(
            activeApp: "Mail", focusSince: now, clipboardSummary: nil,
            openFiles: [], recentActions: [], pendingSuggestion: nil, now: now)
        // Only the active app present → 1 of 4.
        XCTAssertEqual(s.confidence, 0.25, accuracy: 0.001)
    }

    func testWorldStateRoundTrips() throws {
        let s = CurrentWorldState.build(
            activeApp: "Figma", focusSince: Date(), clipboardSummary: "x",
            openFiles: ["a"], recentActions: ["b"], pendingSuggestion: "draft reply", now: Date())
        let decoded = try JSONDecoder().decode(
            CurrentWorldState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testInjectTestStateOverridesWorldState() async {
        let coord = ContextCoordinator()
        let injected = CurrentWorldState.build(
            activeApp: "TestApp", focusSince: nil, clipboardSummary: nil,
            openFiles: [], recentActions: [], pendingSuggestion: nil, now: Date())
        await coord.injectTestState(injected)
        let got = await coord.worldState()
        XCTAssertEqual(got.activeApp, "TestApp")
    }
}
