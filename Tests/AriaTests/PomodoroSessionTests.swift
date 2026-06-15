import XCTest
@testable import Aria

final class PomodoroSessionTests: XCTestCase {

    // Use fresh instances so tests are completely isolated from shared state.

    func testStartSetsFocusingState() async {
        let session = PomodoroSession()
        await session.start(topic: "Writing", minutes: 25)
        let state = await session.state
        XCTAssertEqual(state, .focusing(topic: "Writing"))
    }

    func testTickDecrementsTimer() async {
        let session = PomodoroSession()
        await session.start(topic: "Coding", minutes: 10)
        await session.tick()
        let remaining = await session.minutesRemaining
        XCTAssertEqual(remaining, 9)
    }

    func testTickCompletesSessionAndNotifies() async {
        let session = PomodoroSession()
        var notifyCalled = false
        await session.start(topic: "Reading", minutes: 1)

        // Inject notify closure to capture call.
        await session.setNotify { _, _ in notifyCalled = true }

        await session.tick()  // 1 → 0 → completes

        let state = await session.state
        let completed = await session.completedSessions
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(completed, 1)
        XCTAssertTrue(notifyCalled)
    }

    func testStopEndsSession() async {
        let session = PomodoroSession()
        await session.start(topic: "Planning", minutes: 25)
        let summary = await session.stop()
        let state = await session.state
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(summary.contains("Planning"), "Expected topic in summary: \(summary)")
    }

    func testStatusWhileIdle() async {
        let session = PomodoroSession()
        let status = await session.status()
        XCTAssertTrue(status.contains("No active focus session"))
    }

    func testStatusWhileFocusing() async {
        let session = PomodoroSession()
        await session.start(topic: "Design", minutes: 20)
        let status = await session.status()
        XCTAssertTrue(status.contains("Design"), "Expected topic in status: \(status)")
        XCTAssertTrue(status.contains("20"), "Expected minute count in status: \(status)")
    }

    func testStartClampsMinutes() async {
        let session = PomodoroSession()
        // Clamping happens in PomodoroStartTool, but let's verify the tool clamps correctly.
        let tool = PomodoroStartTool(session: session)
        _ = try? await tool.run(input: ["topic": "Test", "minutes": "200"])
        let remaining = await session.minutesRemaining
        XCTAssertEqual(remaining, 120)
    }

    func testStopWhenIdleReturnsNoSessionMessage() async {
        let session = PomodoroSession()
        let result = await session.stop()
        XCTAssertEqual(result, "No active session.")
    }
}

// MARK: - Test helper

extension PomodoroSession {
    /// Allows tests to inject the notify closure without blocking on MainActor.
    func setNotify(_ closure: @escaping @Sendable (String, String) async -> Void) {
        notify = closure
    }
}
