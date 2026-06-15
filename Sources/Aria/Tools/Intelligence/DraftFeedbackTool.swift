import Foundation

/// Record feedback on a draft Aria wrote — approve it (positive style sample)
/// or reject it (logs intent to improve). Feeds back into `StyleLearner` so
/// future drafts more closely match the user's voice.
struct DraftFeedbackTool: AriaTool {
    static let name = "draft_feedback"
    static let description = "Record feedback on a draft Aria wrote. Input: rating ('approve' or 'reject'), note (optional comment about what to improve)."
    static let paramHints: [String: String] = [
        "rating": "'approve' or 'reject'",
        "note": "Optional comment about what to improve (e.g. 'too formal', 'too long')"
    ]

    var learner: StyleLearner

    init(learner: StyleLearner = StyleLearner.shared) {
        self.learner = learner
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let rawRating = input["rating"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawRating.isEmpty else {
            return .fail("Missing input: rating. Please say 'approve' or 'reject'.")
        }

        let lower = rawRating.lowercased()
        guard lower == "approve" || lower == "reject" else {
            return .fail("Invalid rating \"\(rawRating)\". Use 'approve' or 'reject'.")
        }

        let approved = lower == "approve"
        let note = input["note"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftText = note ?? ""

        await learner.recordFeedback(approved: approved, draftText: draftText)

        if approved {
            return .ok("Got it — I'll keep that style in mind for future drafts.")
        } else {
            return .ok("Noted. I'll adjust my style. Tell me what felt off: too formal? too long? wrong tone?")
        }
    }
}
