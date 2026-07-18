import Foundation

/// One meaningful event on Aria's timeline, in the directive's taxonomy.
struct TimelineEntry: Equatable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case goalCreated, goalAdvanced, resume, taskFinished
        case focusChange, testRun, commitCreated
    }
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
    let ok: Bool
    let project: String?
}

/// TimelineEngine (Phase 2): the *meaningful-event* timeline. It extends the
/// existing `Timeline` aggregation (completed tasks/agent runs + actions) and
/// folds in the continuity sources — GoalEngine (goals created/advanced),
/// SessionMemory (resume points), and ContextCoordinator (the live focus). It
/// OWNS NO STORAGE: every event is derived on read from the stores that already
/// hold the data, so there is no second copy to keep in sync. Deterministic,
/// local-first, deduplicated, and compressed for a quiet, readable history.
actor TimelineEngine {
    static let shared = TimelineEngine()

    private let timeline: Timeline
    private let activity: ActivityLog
    private let goals: GoalEngine
    private let sessions: SessionMemoryStore
    private let context: ContextCoordinator
    private let compressionWindow: TimeInterval
    private var retentionHorizon: Date?

    init(timeline: Timeline = Timeline(),
         activity: ActivityLog = .shared,
         goals: GoalEngine = .shared,
         sessions: SessionMemoryStore = .shared,
         context: ContextCoordinator = .shared,
         compressionWindow: TimeInterval = 90) {
        self.timeline = timeline
        self.activity = activity
        self.goals = goals
        self.sessions = sessions
        self.context = context
        self.compressionWindow = compressionWindow
    }

    // MARK: query

    /// Meaningful events in [from, to), chronological, deduped + compressed.
    func events(from: Date, to: Date, now: Date = Date()) async -> [TimelineEntry] {
        let lo = max(from, retentionHorizon ?? from)
        guard lo < to else { return [] }
        var raw: [TimelineEntry] = []

        // Completed work — reuse the existing Timeline aggregation.
        for e in await timeline.events(from: lo, to: to) where e.source == .task || e.source == .agent {
            let prefix = e.source == .agent ? "agent: " : ""
            raw.append(TimelineEntry(date: e.date, kind: .taskFinished, title: e.title,
                                     detail: prefix + e.detail, ok: e.ok, project: e.project))
        }

        // Actions worth keeping: test runs and commits (everything else is noise).
        for a in await activity.entries(from: lo, to: to) {
            guard let kind = Self.actionKind(tool: a.tool, detail: a.detail, summary: a.summary) else { continue }
            raw.append(TimelineEntry(date: a.date, kind: kind, title: a.detail.isEmpty ? a.tool : a.detail,
                                     detail: a.summary, ok: a.outcome == .ok, project: nil))
        }

        // Goals — created, and advanced when touched after creation.
        for g in await goals.all() {
            if g.createdAt >= lo && g.createdAt < to {
                raw.append(TimelineEntry(date: g.createdAt, kind: .goalCreated, title: g.title,
                                         detail: g.project ?? "", ok: true, project: g.project))
            }
            if g.updatedAt > g.createdAt && g.updatedAt >= lo && g.updatedAt < to {
                raw.append(TimelineEntry(date: g.updatedAt, kind: .goalAdvanced, title: g.title,
                                         detail: g.nextAction ?? g.status.rawValue, ok: true, project: g.project))
            }
        }

        // Resume points — each saved session snapshot is a "continue here" marker.
        for snap in await sessions.active(now: now) where snap.date >= lo && snap.date < to {
            raw.append(TimelineEntry(date: snap.date, kind: .resume, title: snap.goal,
                                     detail: snap.nextStep ?? snap.progress, ok: true, project: snap.project))
        }

        // The live focus (no focus history is stored, so this is the current one).
        let world = await context.worldState(now: now)
        if !world.activeApp.isEmpty {
            let since = world.timestamp.addingTimeInterval(-world.focusDuration)
            if since >= lo && since < to {
                raw.append(TimelineEntry(date: since, kind: .focusChange, title: world.activeApp,
                                         detail: "focused", ok: true, project: nil))
            }
        }

        return compress(dedupe(raw.sorted { $0.date < $1.date }))
    }

    /// Newest-first meaningful events, capped at `limit` (default window: 30 days).
    func recent(_ limit: Int, now: Date = Date()) async -> [TimelineEntry] {
        let from = now.addingTimeInterval(-30 * 86_400)
        let all = await events(from: from, to: now.addingTimeInterval(1), now: now)
        return Array(all.reversed().prefix(limit))
    }

    /// Per-day digest with completion counts — "what did I do today / this week".
    func summarize(from: Date, to: Date, itemsPerDay: Int = 6,
                   calendar: Calendar = .current, now: Date = Date()) async -> String {
        let all = await events(from: from, to: to, now: now)
        guard !all.isEmpty else { return "" }
        let byDay = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted().map { dayStart in
            let dayEvents = byDay[dayStart] ?? []
            let done = dayEvents.filter(\.ok).count
            let failed = dayEvents.count - done
            let header = dayStart.formatted(.dateTime.month(.abbreviated).day())
                + " — \(done) done" + (failed > 0 ? ", \(failed) failed" : "")
            let lines = dayEvents.prefix(itemsPerDay).map { "  \(glyph(for: $0.kind)) \($0.title)" }
            let more = dayEvents.count > itemsPerDay
                ? ["  … and \(dayEvents.count - itemsPerDay) more"] : []
            return ([header] + lines + more).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// Forget events before `date`. The engine owns no storage, so this is a read
    /// horizon — durable stores keep their own caps; this keeps the *view* tidy.
    func prune(before date: Date) {
        retentionHorizon = max(retentionHorizon ?? date, date)
    }

    /// Deterministic resume line for "continue" — the active goal (+ next action +
    /// blockers), else the last session snapshot, else the most recent work.
    /// Pure local reads; no model call, so it returns well under the <2s target.
    func resumeBrief(project: String? = nil, now: Date = Date()) async -> String {
        if let goal = await goals.continueDigest(project: project) { return "Continue: \(goal)" }
        if let snap = await sessions.resumeDigest(project: project, now: now) { return "Continue: \(snap)" }
        let recent = await recent(1, now: now)
        if let last = recent.first { return "Last: \(last.title)" }
        return "Nothing in progress."
    }

    // MARK: internals

    /// Classify an action into a meaningful timeline kind, or nil to drop it.
    static func actionKind(tool: String, detail: String, summary: String) -> TimelineEntry.Kind? {
        let t = tool.lowercased()
        let blob = (detail + " " + summary).lowercased()
        if t.contains("test") || blob.contains("swift test") || blob.contains("xctest") { return .testRun }
        if t.contains("commit") || blob.contains("git commit") || blob.contains("commit -m") { return .commitCreated }
        return nil
    }

    /// Drop exact repeats (same instant, kind, and title).
    private func dedupe(_ sorted: [TimelineEntry]) -> [TimelineEntry] {
        var seen = Set<String>()
        return sorted.filter { e in
            seen.insert("\(e.date.timeIntervalSince1970)|\(e.kind.rawValue)|\(e.title)").inserted
        }
    }

    /// Collapse a run of the same (kind, title) whose entries are each within
    /// `compressionWindow` of the kept one — quiets repetitive noise (re-runs,
    /// focus flapping) without merging genuinely separate events.
    private func compress(_ sorted: [TimelineEntry]) -> [TimelineEntry] {
        var out: [TimelineEntry] = []
        for e in sorted {
            if let last = out.last, last.kind == e.kind, last.title == e.title,
               e.date.timeIntervalSince(last.date) <= compressionWindow {
                continue
            }
            out.append(e)
        }
        return out
    }

    private func glyph(for kind: TimelineEntry.Kind) -> String {
        switch kind {
        case .goalCreated:   return "◆"
        case .goalAdvanced:  return "▸"
        case .resume:        return "↻"
        case .taskFinished:  return "✓"
        case .focusChange:   return "○"
        case .testRun:       return "⚑"
        case .commitCreated: return "⊕"
        }
    }
}
