import XCTest
@testable import Aria

final class NotificationBridgeTests: XCTestCase {

    // MARK: Helpers

    /// Sendable box so capture-by-reference works across actor boundaries.
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T?
        func set(_ v: T) { lock.withLock { _value = v } }
        var value: T? { lock.withLock { _value } }
    }

    /// Make a fresh NotificationBridge with injected closures so no real
    /// UNUserNotificationCenter is touched.
    private func makeBridge(
        onDeliver: @escaping @Sendable (String, String) -> Void
    ) async -> NotificationBridge {
        let bridge = NotificationBridge()
        await bridge.setRequestPermission { true }
        await bridge.setDeliver { title, body in onDeliver(title, body) }
        return bridge
    }

    // MARK: Tests

    func testAgentCompletedNotification() async {
        let box = Box<(String, String)>()
        let bridge = await makeBridge { title, body in box.set((title, body)) }

        await bridge.send(.agentCompleted(name: "Morning Digest", summary: "Emails summarised."))

        XCTAssertNotNil(box.value)
        XCTAssertTrue(box.value?.0.contains("done") == true,
                      "Title should contain 'done', got: \(box.value?.0 ?? "")")
        XCTAssertEqual(box.value?.1, "Emails summarised.")
    }

    func testFollowUpOverdueNotification() async {
        let box = Box<(String, String)>()
        let bridge = await makeBridge { title, body in box.set((title, body)) }

        await bridge.send(.followUpOverdue(subject: "Project update", recipient: "alice@example.com"))

        XCTAssertTrue(box.value?.1.contains("alice@example.com") == true,
                      "Body should contain recipient, got: \(box.value?.1 ?? "")")
    }

    func testLectureSessionEndedNotification() async {
        let box = Box<(String, String)>()
        let bridge = await makeBridge { title, body in box.set((title, body)) }

        await bridge.send(.lectureSessionEnded(title: "Swift Concurrency", noteCount: 7))

        XCTAssertTrue(box.value?.1.contains("7") == true,
                      "Body should contain note count, got: \(box.value?.1 ?? "")")
    }

    func testMeetingSessionEndedNotification() async {
        let box = Box<(String, String)>()
        let bridge = await makeBridge { title, body in box.set((title, body)) }

        await bridge.send(.meetingSessionEnded(title: "Design Review", actionCount: 3))

        XCTAssertTrue(box.value?.1.contains("3") == true,
                      "Body should contain action count, got: \(box.value?.1 ?? "")")
    }

    func testResearchCompletedNotification() async {
        let box = Box<(String, String)>()
        let bridge = await makeBridge { title, body in box.set((title, body)) }

        await bridge.send(.researchCompleted(topic: "SwiftUI performance", sourceCount: 12))

        XCTAssertTrue(box.value?.1.contains("12") == true,
                      "Body should contain source count, got: \(box.value?.1 ?? "")")
    }

    func testAutomationFiredNotification() async {
        let titleBox = Box<String>()
        let bodyBox = Box<String>()
        let bridge = await makeBridge { title, body in
            titleBox.set(title)
            bodyBox.set(body)
        }

        await bridge.send(.automationFired(name: "Send daily report"))

        XCTAssertTrue(titleBox.value?.contains("Send daily report") == true,
                      "Title should contain automation name, got: \(titleBox.value ?? "")")
        XCTAssertEqual(bodyBox.value, "Aria ran your automation.")
    }

    func testRequestPermissionIfNeeded() async {
        let bridge = NotificationBridge()
        await bridge.setRequestPermission { true }
        await bridge.setDeliver { _, _ in }

        let granted = await bridge.requestPermissionIfNeeded()
        XCTAssertTrue(granted)

        // Second call should use cached value without calling the closure again.
        let callCount = LockBox(0)
        await bridge.setRequestPermission {
            callCount.value += 1
            return false
        }
        let grantedAgain = await bridge.requestPermissionIfNeeded()
        XCTAssertTrue(grantedAgain, "Should return cached value")
        XCTAssertEqual(callCount.value, 0, "Should not call closure again when cached")
    }
}

/// Simple lock-protected mutable box for sharing state across actor boundaries in tests.
private final class LockBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
