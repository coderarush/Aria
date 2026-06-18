import XCTest
@testable import Aria

@MainActor
final class PresenceRuntimeTests: XCTestCase {

    func testIdleMappings() {
        XCTAssertEqual(PresenceRuntime.state(island: .idle), .idle)
        XCTAssertEqual(PresenceRuntime.state(island: .idle, hasSuggestion: true), .aware)
    }

    func testListeningIsAware() {
        XCTAssertEqual(PresenceRuntime.state(island: .listening), .aware)
    }

    func testThinkingVsPlanning() {
        XCTAssertEqual(PresenceRuntime.state(island: .thinking), .thinking)
        XCTAssertEqual(PresenceRuntime.state(island: .thinking, isPlanning: true), .planning)
    }

    func testExecutingIsActing() {
        XCTAssertEqual(PresenceRuntime.state(island: .executing), .acting)
    }

    func testRespondingIsComplete() {
        XCTAssertEqual(PresenceRuntime.state(island: .responding), .complete)
    }

    func testErrorIsWaiting() {
        XCTAssertEqual(PresenceRuntime.state(island: .error), .waiting)
    }

    func testApprovalOverridesToWaiting() {
        // Awaiting a real approval is a genuine waiting state, whatever the island shows.
        XCTAssertEqual(PresenceRuntime.state(island: .executing, awaitingApproval: true), .waiting)
    }

    func testModeIsBlobWhenActiveHiddenWhenIdleInvisible() {
        XCTAssertEqual(PresenceRuntime.mode(for: .acting, visible: true), .blob)
        XCTAssertEqual(PresenceRuntime.mode(for: .aware, visible: false), .blob)   // aware still shows
        XCTAssertEqual(PresenceRuntime.mode(for: .idle, visible: false), .hidden)
        XCTAssertEqual(PresenceRuntime.mode(for: .idle, visible: true), .blob)
    }

    func testActiveFlagAndLabels() {
        XCTAssertFalse(PresenceState.idle.isActive)
        XCTAssertTrue(PresenceState.acting.isActive)
        XCTAssertFalse(PresenceState.acting.label.isEmpty)
    }
}
