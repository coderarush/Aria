import Foundation

/// The state needed to pick work back up — assembled, never stored.
struct RestoreState: Equatable, Sendable {
    var inFlightTask: String?
    var resumeIndex: Int?
    var unfinishedSteps: Int
    var brief: String
    var openLoops: [String]
    var recentChanges: [String]
    var suggestedNext: String?
    var confidence: Double

    func text() -> String {
        var parts: [String] = []
        if let task = inFlightTask {
            parts.append("Resuming ‘\(task)’ at step \((resumeIndex ?? 0) + 1) (\(unfinishedSteps) left)")
        }
        parts.append(brief)
        if let next = suggestedNext { parts.append("Next: \(next)") }
        if !openLoops.isEmpty { parts.append("Open loops: \(openLoops.joined(separator: ", "))") }
        if !recentChanges.isEmpty { parts.append("Changed: \(recentChanges.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }
}

/// ResumeEngine (Phase 6): the deterministic restore for "continue" — restore
/// the interrupted task, summarise where things stand, surface open loops, and
/// suggest the next step. It adds NO storage and duplicates NO logic: the
/// continuity line is `TimelineEngine.resumeBrief` (reused as-is), the interrupted
/// task comes from the existing `TaskStore`, loops from `GoalEngine`, changes from
/// the timeline. Pure local reads — the <2s restore path, no model call.
struct ResumeEngine {
    private let tasks: TaskStore
    private let goals: GoalEngine
    private let timeline: TimelineEngine

    init(tasks: TaskStore = .shared, goals: GoalEngine = .shared, timeline: TimelineEngine = .shared) {
        self.tasks = tasks
        self.goals = goals
        self.timeline = timeline
    }

    func restore(project: String? = nil, now: Date = Date()) async -> RestoreState {
        let pending = await tasks.pending()
        let brief = await timeline.resumeBrief(project: project, now: now)
        let active = await goals.active().filter {
            project == nil || $0.project?.lowercased() == project?.lowercased()
        }
        let openLoops = active.prefix(5).map(\.title)
        let recentChanges = (await timeline.recent(3, now: now)).map(\.title)

        let suggestedNext: String?
        if let p = pending {
            suggestedNext = "resume ‘\(p.goal)’ at step \(p.resumeIndex + 1)"
        } else {
            suggestedNext = active.first(where: { $0.nextAction?.isEmpty == false })?.nextAction
        }

        let populated = [pending != nil, !openLoops.isEmpty,
                         !recentChanges.isEmpty, suggestedNext != nil].filter { $0 }.count

        return RestoreState(inFlightTask: pending?.goal,
                            resumeIndex: pending?.resumeIndex,
                            unfinishedSteps: pending?.unfinishedCount ?? 0,
                            brief: brief,
                            openLoops: Array(openLoops),
                            recentChanges: recentChanges,
                            suggestedNext: suggestedNext,
                            confidence: Double(populated) / 4.0)
    }
}
