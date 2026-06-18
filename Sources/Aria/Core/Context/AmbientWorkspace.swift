import Foundation

/// The always-available ambient surface state — goal, focus, progress, open loops,
/// next action, recent activity. A lightweight value, assembled on demand.
struct WorkspaceState: Equatable, Sendable {
    var goal: String?
    var focus: String?
    var progress: Double?
    var openLoops: [String]
    var nextAction: String?
    var recentActivity: [String]
    var confidence: Double
}

/// AmbientWorkspace (Phase 7): the lightweight, low-distraction surface model.
/// It is data only — a `WorkspaceState` composed on demand from the engines that
/// already own everything (GoalEngine, TimelineEngine, ContextCoordinator). No
/// storage, no SwiftUI here: rendering this into the island is left to the
/// Presence layer, so the surface and its data stay decoupled.
struct AmbientWorkspace {
    private let goals: GoalEngine
    private let timeline: TimelineEngine
    private let context: ContextCoordinator

    init(goals: GoalEngine = .shared, timeline: TimelineEngine = .shared,
         context: ContextCoordinator = .shared) {
        self.goals = goals
        self.timeline = timeline
        self.context = context
    }

    func snapshot(now: Date = Date()) async -> WorkspaceState {
        let active = await goals.active()
        let top = active.first
        let openLoops = active.prefix(4).map(\.title)

        let world = await context.worldState(now: now)
        let focus = world.activeApp.isEmpty ? nil : world.activeApp

        let recentActivity = (await timeline.recent(3, now: now)).map(\.title)

        let populated = [top != nil, focus != nil, !openLoops.isEmpty, !recentActivity.isEmpty]
            .filter { $0 }.count

        return WorkspaceState(goal: top?.title,
                              focus: focus,
                              progress: top?.progress,
                              openLoops: Array(openLoops),
                              nextAction: top?.nextAction,
                              recentActivity: recentActivity,
                              confidence: Double(populated) / 4.0)
    }
}
