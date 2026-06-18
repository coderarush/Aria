import Foundation

/// Daily review / wrap up / prepare tomorrow (Phase 11). Thin surface over
/// DailyReviewEngine — output only, no persistence.
struct DailyReviewTool: AriaTool {
    static let name = "daily_review"
    static let description = "Daily review — wins, progress, what's unfinished, and tomorrow's focus. Input: {}. Use for ‘daily review’, ‘wrap up’, ‘prepare tomorrow’, ‘how did today go’."

    private let engine: DailyReviewEngine
    private let now: () -> Date

    init(engine: DailyReviewEngine = DailyReviewEngine(), now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.now = now
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let review = await engine.review(now: now())
        return .ok(review.text())
    }
}
