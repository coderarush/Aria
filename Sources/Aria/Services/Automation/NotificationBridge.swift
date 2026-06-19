import Foundation
import UserNotifications

/// The kinds of events Aria can surface as system notifications.
enum AriaNotificationEvent {
    case agentCompleted(name: String, summary: String)
    case automationFired(name: String)
    case followUpOverdue(subject: String, recipient: String)
    case lectureSessionEnded(title: String, noteCount: Int)
    case meetingSessionEnded(title: String, actionCount: Int)
    case researchCompleted(topic: String, sourceCount: Int)
}

/// Converts semantic Aria events into UNUserNotification deliveries.
/// All UNUserNotificationCenter interactions are injected so tests never
/// touch the real notification subsystem.
actor NotificationBridge {
    static let shared = NotificationBridge()

    /// Injectable for tests — defaults to real UNUserNotificationCenter authorization.
    var requestPermission: @Sendable () async -> Bool

    /// Injectable for tests — defaults to real UNUserNotificationCenter delivery.
    var deliver: @Sendable (String, String) async -> Void

    private var permissionGranted: Bool?

    /// Set the permission-request closure (for testing from async contexts).
    func setRequestPermission(_ closure: @escaping @Sendable () async -> Bool) {
        requestPermission = closure
    }

    /// Set the deliver closure (for testing from async contexts).
    func setDeliver(_ closure: @escaping @Sendable (String, String) async -> Void) {
        deliver = closure
    }

    init() {
        requestPermission = {
            do {
                return try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        }

        deliver = { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Request notification permission if not already determined. Returns whether
    /// permission is granted. Result is cached for subsequent calls.
    func requestPermissionIfNeeded() async -> Bool {
        if let cached = permissionGranted { return cached }
        let granted = await requestPermission()
        permissionGranted = granted
        return granted
    }

    /// Map the event to a (title, body) pair and deliver it.
    func send(_ event: AriaNotificationEvent) async {
        let (title, body) = Self.content(for: event)
        await deliver(title, body)
    }

    // MARK: Private mapping

    private static func content(for event: AriaNotificationEvent) -> (String, String) {
        switch event {
        case .agentCompleted(let name, let summary):
            return ("Aria: \(name) done", summary)
        case .automationFired(let name):
            return ("Automation: \(name)", "Aria ran your automation.")
        case .followUpOverdue(let subject, let recipient):
            return ("Follow-up needed", "No reply from \(recipient) on \"\(subject)\"")
        case .lectureSessionEnded(let title, let noteCount):
            return ("Notes saved", "\(noteCount) sections captured for \"\(title)\"")
        case .meetingSessionEnded(let title, let actionCount):
            return ("Meeting notes saved", "\(actionCount) action items from \"\(title)\"")
        case .researchCompleted(let topic, let sourceCount):
            return ("Research complete", "\(sourceCount) sources synthesized on \"\(topic)\"")
        }
    }
}
