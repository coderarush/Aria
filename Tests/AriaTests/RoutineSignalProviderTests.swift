import XCTest
@testable import Aria

final class RoutineSignalProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func pattern(_ id: UUID, desc: String, confidence: Double) -> BehaviorPattern {
        BehaviorPattern(
            id: id,
            description: desc,
            trigger: .timeOfDay(hour: 9, minute: 0, days: [.monday]),
            action: .runSavedCommand("open slack"),
            confidence: confidence,
            occurrences: [])
    }

    func testMapsPatternToAmbientSuggestion() async {
        let id = UUID()
        let p = pattern(id, desc: "Open Slack at 9am", confidence: 0.8)
        let provider = RoutineSignalProvider { _ in [p] }
        let out = await provider.candidates(now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .routine)
        XCTAssertEqual(out[0].urgency, .ambient)
        XCTAssertEqual(out[0].confidence, 0.8)
        XCTAssertEqual(out[0].action, .offerAutomation(patternID: id))
        XCTAssertEqual(out[0].dedupeKey, "routine:\(id.uuidString)")
        XCTAssertTrue(out[0].spokenLine.contains("Open Slack at 9am"))
    }

    func testEmptyWhenNoPatterns() async {
        let provider = RoutineSignalProvider { _ in [] }
        let out = await provider.candidates(now: now)
        XCTAssertTrue(out.isEmpty)
    }
}
