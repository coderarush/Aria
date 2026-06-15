import Foundation

/// Lists overdue email follow-ups the user is waiting for replies on.
struct FollowUpTool: AriaTool {
    static let name = "followup_check"
    static let description = "Check for overdue email follow-ups — emails you sent where no reply has come back within the expected window."

    func run(input: [String: String]) async throws -> ToolResult {
        let overdue = await FollowUpTracker.shared.overdue()
        guard !overdue.isEmpty else {
            return .ok("All caught up! No overdue follow-ups.")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let lines = overdue.enumerated().map { idx, item -> String in
            let sent = dateFormatter.string(from: item.sentDate)
            return "\(idx + 1). \"\(item.subject)\" → \(item.recipient) (sent \(sent))"
        }
        return .ok("Overdue follow-ups:\n\(lines.joined(separator: "\n"))")
    }
}
