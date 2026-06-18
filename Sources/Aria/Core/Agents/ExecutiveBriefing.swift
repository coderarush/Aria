import Foundation

/// ExecutiveBriefing (Phase 3): a short, deterministic "where do things stand /
/// what next" snapshot. OUTPUT ONLY — it holds no state and composes the engines
/// that already own the data (GoalEngine, TimelineEngine, ContextCoordinator).
/// Distinct from BriefingComposer, which is the model-composed *daily* briefing
/// over calendar/reminders/notes; this is the instant goal-centric status.
struct ExecutiveBriefing {

    struct Output: Equatable, Sendable {
        var currentFocus: String?
        var recentProgress: [String]
        var openLoops: [String]
        var blocked: [String]
        var nextAction: String?
        var risks: [String]
        var confidence: Double

        /// Compact, header-light text — empty sections are skipped.
        func text() -> String {
            var parts: [String] = []
            if let f = currentFocus { parts.append("Focus: \(f)") }
            if let n = nextAction { parts.append("Next: \(n)") }
            if !openLoops.isEmpty { parts.append("Open loops: \(openLoops.joined(separator: ", "))") }
            if !blocked.isEmpty { parts.append("Blocked: \(blocked.joined(separator: "; "))") }
            if !recentProgress.isEmpty { parts.append("Recent: \(recentProgress.joined(separator: ", "))") }
            if !risks.isEmpty { parts.append("Risks: \(risks.joined(separator: "; "))") }
            parts.append("(confidence \(Int(confidence * 100))%)")
            return parts.joined(separator: "\n")
        }
    }

    private let goals: GoalEngine
    private let timeline: TimelineEngine
    private let context: ContextCoordinator

    init(goals: GoalEngine = .shared, timeline: TimelineEngine = .shared,
         context: ContextCoordinator = .shared) {
        self.goals = goals
        self.timeline = timeline
        self.context = context
    }

    func compose(project: String? = nil, now: Date = Date()) async -> Output {
        let active = await goals.active().filter {
            project == nil || $0.project?.lowercased() == project?.lowercased()
        }
        let openLoops = active.prefix(5).map(\.title)
        let nextAction = active.first(where: { $0.nextAction?.isEmpty == false })?.nextAction

        let blocked = (await goals.blockers())
            .filter { b in project == nil || active.contains { $0.id == b.goalID } }
            .map { "\($0.blocker) (\($0.goalTitle))" }

        let progress = (await timeline.recent(4, now: now))
            .filter { $0.kind == .taskFinished || $0.kind == .goalAdvanced }
            .map(\.title)
        var seenP = Set<String>()
        let recentProgress = progress.filter { seenP.insert($0).inserted }.prefix(3).map { $0 }

        let world = await context.worldState(now: now)
        let currentFocus = world.activeApp.isEmpty ? nil
            : "\(world.activeApp) (\(Int(world.focusDuration / 60))m)"

        // Risk alerts: blockers, plus active goals with no next step defined.
        var risks = blocked
        risks += active.filter { $0.nextAction?.isEmpty != false }.map { "no next step: \($0.title)" }

        let populated = [currentFocus != nil, !recentProgress.isEmpty,
                         !openLoops.isEmpty, nextAction != nil].filter { $0 }.count
        let confidence = Double(populated) / 4.0

        return Output(currentFocus: currentFocus,
                      recentProgress: Array(recentProgress),
                      openLoops: Array(openLoops),
                      blocked: blocked,
                      nextAction: nextAction,
                      risks: risks,
                      confidence: confidence)
    }
}
