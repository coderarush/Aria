import Foundation

/// One milestone on the path to a goal.
struct Milestone: Codable, Equatable, Sendable {
    let id: String
    var title: String
    var done: Bool

    init(id: String = UUID().uuidString, title: String, done: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// Lifecycle of a goal.
enum GoalStatus: String, Codable, Sendable {
    case active
    case done
    case archived
}

/// A durable objective Aria tracks across sessions — the thing everything else
/// (timeline, briefing, work sessions) attaches to. Unlike `SessionSnapshot`
/// (ephemeral, TTL-expiring resume state) and `WorkEntry` (a completed-work log),
/// a Goal is the standing target with milestones, blockers, and a next action.
struct Goal: Codable, Equatable, Sendable {
    let id: String
    var title: String
    var project: String?
    var milestones: [Milestone]
    var blockers: [String]
    var nextAction: String?
    var status: GoalStatus
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         project: String? = nil,
         milestones: [Milestone] = [],
         blockers: [String] = [],
         nextAction: String? = nil,
         status: GoalStatus = .active,
         createdAt: Date = Date(),
         updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.project = project
        self.milestones = milestones
        self.blockers = blockers
        self.nextAction = nextAction
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Fraction complete in [0, 1]. A finished goal is always 1; otherwise it's the
    /// share of milestones done (0 when there are none yet). Derived, never stored.
    var progress: Double {
        if status == .done { return 1 }
        guard !milestones.isEmpty else { return 0 }
        let done = milestones.filter(\.done).count
        return Double(done) / Double(milestones.count)
    }
}

/// An open blocker surfaced with the goal it belongs to — feeds "show blockers".
struct OpenBlocker: Equatable, Sendable {
    let goalID: String
    let goalTitle: String
    let blocker: String
}

/// Goal Engine (Phase 1): durable, local-first goal tracking. Everything attaches
/// to goals. Persists to disk, evicts oldest beyond `cap`, nothing leaves the
/// machine. Complements WorkJournal/SessionMemory/Timeline — does not replace them.
actor GoalEngine {
    static let shared = GoalEngine()

    private let fileURL: URL
    private let cap: Int
    private var goals: [Goal]

    init(fileURL: URL? = nil, cap: Int = 500) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("goals.json")
        self.fileURL = url
        self.cap = cap
        self.goals = Self.load(from: url)
    }

    // MARK: create

    /// Create a goal. Returns nil for a blank title (nothing to track).
    @discardableResult
    func create(title: String, project: String? = nil, now: Date = Date()) -> Goal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let goal = Goal(title: trimmed, project: project, createdAt: now)
        goals.append(goal)
        if goals.count > cap { goals.removeFirst(goals.count - cap) }
        save()
        return goal
    }

    // MARK: read

    func goal(id: String) -> Goal? { goals.first { $0.id == id } }

    /// Every goal, newest-created first — full history for the timeline (includes
    /// done/archived). `active()` is the live working set; this is the record.
    func all() -> [Goal] { goals.sorted { $0.createdAt > $1.createdAt } }

    /// Active goals, most recently updated first — the live working set.
    func active() -> [Goal] {
        goals.filter { $0.status == .active }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Every open blocker across active goals — "show blockers".
    func blockers() -> [OpenBlocker] {
        active().flatMap { g in
            g.blockers.map { OpenBlocker(goalID: g.id, goalTitle: g.title, blocker: $0) }
        }
    }

    /// Resume line for the top active goal (optionally project-scoped, case-insensitive)
    /// — goal + next action + blockers. Powers "continue goal". Nil when nothing's active.
    func continueDigest(project: String? = nil) -> String? {
        let candidates = active().filter {
            project == nil || $0.project?.lowercased() == project?.lowercased()
        }
        guard let g = candidates.first else { return nil }
        var line = g.title
        if let next = g.nextAction, !next.isEmpty { line += " — next: \(next)" }
        if !g.blockers.isEmpty { line += " (blocked on: \(g.blockers.joined(separator: ", ")))" }
        return line
    }

    // MARK: advance

    @discardableResult
    func addMilestone(goalID: String, title: String, now: Date = Date()) -> Milestone? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let milestone = Milestone(title: trimmed)
        let ok = mutate(goalID, now: now) { $0.milestones.append(milestone) }
        return ok ? milestone : nil
    }

    @discardableResult
    func completeMilestone(goalID: String, milestoneID: String, now: Date = Date()) -> Bool {
        mutate(goalID, now: now) { g in
            guard let i = g.milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
            g.milestones[i].done = true
        }
    }

    @discardableResult
    func setNextAction(goalID: String, _ action: String?, now: Date = Date()) -> Bool {
        mutate(goalID, now: now) { $0.nextAction = action }
    }

    @discardableResult
    func addBlocker(goalID: String, _ blocker: String, now: Date = Date()) -> Bool {
        let trimmed = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return mutate(goalID, now: now) { g in
            guard !g.blockers.contains(trimmed) else { return }
            g.blockers.append(trimmed)
        }
    }

    @discardableResult
    func clearBlocker(goalID: String, _ blocker: String, now: Date = Date()) -> Bool {
        mutate(goalID, now: now) { $0.blockers.removeAll { $0 == blocker } }
    }

    @discardableResult
    func complete(goalID: String, now: Date = Date()) -> Bool {
        mutate(goalID, now: now) { $0.status = .done }
    }

    @discardableResult
    func archive(goalID: String, now: Date = Date()) -> Bool {
        mutate(goalID, now: now) { $0.status = .archived }
    }

    // MARK: internals

    /// Apply an edit to one goal, bump its updatedAt, and persist. Returns false
    /// if no goal matched.
    private func mutate(_ id: String, now: Date, _ edit: (inout Goal) -> Void) -> Bool {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { return false }
        edit(&goals[i])
        goals[i].updatedAt = now
        save()
        return true
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(goals) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [Goal] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([Goal].self, from: data)) ?? []
    }
}
