import Foundation

/// A day's compounding review — assembled on demand, never stored.
struct DailyReview: Equatable, Sendable {
    var wins: [String]
    var progress: [String]
    var unfinished: [String]
    var tomorrow: [String]

    func text() -> String {
        func section(_ title: String, _ items: [String]) -> String? {
            items.isEmpty ? nil : "\(title):\n" + items.map { "  • \($0)" }.joined(separator: "\n")
        }
        let blocks = [section("Wins", wins), section("Progress", progress),
                      section("Unfinished", unfinished), section("Tomorrow", tomorrow)].compactMap { $0 }
        return blocks.isEmpty ? "Quiet day — nothing logged yet." : blocks.joined(separator: "\n")
    }
}

/// DailyReviewEngine (Phase 11): "daily review / wrap up / prepare tomorrow".
/// Mirrors DigestEngine's shape but adds the compounding view — wins, progress,
/// unfinished, tomorrow. NO persistence: it composes today's data from the
/// engines that already own it (TimelineEngine for completed work + goal advances,
/// GoalEngine for open loops + next actions).
struct DailyReviewEngine {
    private let timeline: TimelineEngine
    private let goals: GoalEngine

    init(timeline: TimelineEngine = .shared, goals: GoalEngine = .shared) {
        self.timeline = timeline
        self.goals = goals
    }

    func review(now: Date = Date(), calendar: Calendar = .current) async -> DailyReview {
        let dayStart = calendar.startOfDay(for: now)
        let todays = await timeline.events(from: dayStart, to: now.addingTimeInterval(1), now: now)

        var seenWin = Set<String>()
        let wins = todays.filter { $0.kind == .taskFinished && $0.ok }
            .map(\.title).filter { seenWin.insert($0).inserted }

        var seenProg = Set<String>()
        let progress = todays.filter { $0.kind == .goalAdvanced }
            .map { "advanced \($0.title)" }.filter { seenProg.insert($0).inserted }

        let active = await goals.active()
        let unfinished = active.prefix(6).map { g -> String in
            if let n = g.nextAction, !n.isEmpty { return "\(g.title) — \(n)" }
            return g.title
        }

        let tomorrow = active.compactMap { g -> String? in
            guard let n = g.nextAction, !n.isEmpty else { return nil }
            return "\(n) (\(g.title))"
        }.prefix(3).map { $0 }

        return DailyReview(wins: wins, progress: progress,
                           unfinished: Array(unfinished), tomorrow: Array(tomorrow))
    }
}
